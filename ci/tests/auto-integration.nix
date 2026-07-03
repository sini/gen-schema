# Tests for auto-extraction of refinements from types and auto-application of mixins.
# These verify the spec's promise: refinements co-located with types are extracted
# automatically, and mkSchemaEntryType { mixins = [...] } applies them without manual
# applyMixin + emitModule calls.
{
  lib,
  genSchema,
  genMerge,
  genAlgebra,
  ...
}:
let
  inherit (genSchema) mkSchemaOption mkSchemaEntryType mkInstanceRegistry;
  R = genAlgebra.record;
  refinedLib = import ../../lib/refined.nix;

  # --- Test 1: Auto-extracted refinements from inline type declarations ---

  schemaWithRefinedTypes = genMerge.evalModuleTree {
    modules = [
      {
        options.schema = mkSchemaOption { };
        config.schema.service = {
          options.port = genMerge.mkOption {
            type = refinedLib.types.refined genMerge.types.int {
              check = v: v > 0 && v < 65536;
              message = "must be valid TCP port";
            };
          };
          options.name = genMerge.mkOption { type = genMerge.types.str; };
        };
      }
    ];
  };

  schemaR = schemaWithRefinedTypes.config.schema;

  # mkInstanceRegistry without explicit refinements — should auto-extract
  autoRegistry = mkInstanceRegistry schemaR.service { };

  validEval = genMerge.evalModuleTree {
    modules = [
      {
        options.services = autoRegistry;
        config.services.web = {
          port = 8080;
          name = "web";
        };
      }
    ];
  };

  invalidEval = genMerge.evalModuleTree {
    modules = [
      {
        options.services = autoRegistry;
        config.services.bad = {
          port = -1;
          name = "bad";
        };
      }
    ];
  };

  # --- Test 2: Auto-applied mixins in mkSchemaEntryType ---

  monitorable = genSchema.mkMixin {
    requires = [ "port" ];
    provides = [ "metrics_port" ];
    define = parent: {
      metrics_port = genMerge.mkOption {
        type = genMerge.types.int;
        default = (R.select parent "port").default or 9090;
      };
    };
  };

  schemaWithMixins = genMerge.evalModuleTree {
    modules = [
      {
        options.schema = mkSchemaOption {
          mixins = [ monitorable ];
          baseModule = {
            port = genMerge.mkOption {
              type = genMerge.types.int;
              default = 8080;
            };
            hostname = genMerge.mkOption { type = genMerge.types.str; };
          };
        };
        config.schema.service = { };
      }
    ];
  };

  schemaM = schemaWithMixins.config.schema;
  mixinRegistry = mkInstanceRegistry schemaM.service { };

  mixinEval = genMerge.evalModuleTree {
    modules = [
      {
        options.services = mixinRegistry;
        config.services.web = {
          port = 3000;
          hostname = "localhost";
        };
      }
    ];
  };
in
{
  # Auto-extracted refinements: valid value passes
  flake.tests.auto-integration.test-auto-refinement-valid = {
    expr = validEval.config.services.web.port;
    expected = 8080;
  };

  # Auto-extracted refinements: invalid value throws
  flake.tests.auto-integration.test-auto-refinement-invalid-throws = {
    expr = builtins.tryEval (builtins.deepSeq invalidEval.config.services { });
    expected = {
      success = false;
      value = false;
    };
  };

  # Auto-extracted refinements: schema kind has refinements attr
  flake.tests.auto-integration.test-schema-kind-has-refinements = {
    expr = schemaR.service ? refinements;
    expected = true;
  };

  # Auto-extracted refinements: refinements map has the refined field
  flake.tests.auto-integration.test-refinements-has-port = {
    expr = schemaR.service.refinements ? port;
    expected = true;
  };

  # Auto-applied mixins: mixin-provided option exists
  flake.tests.auto-integration.test-auto-mixin-option-exists = {
    expr = mixinEval.config.services.web ? metrics_port;
    expected = true;
  };

  # Auto-applied mixins: base fields preserved
  flake.tests.auto-integration.test-auto-mixin-base-preserved = {
    expr = mixinEval.config.services.web.hostname;
    expected = "localhost";
  };
}
