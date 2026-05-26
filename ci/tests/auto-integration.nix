# Tests for auto-extraction of refinements from types and auto-application of mixins.
# These verify the spec's promise: refinements co-located with types are extracted
# automatically, and mkSchemaEntryType { mixins = [...] } applies them without manual
# applyMixin + emitModule calls.
{
  lib,
  schemaLib,
  genLib,
  ...
}:
let
  inherit (schemaLib) mkSchemaOption mkSchemaEntryType mkInstanceRegistry;
  R = genLib.record;
  refinedLib = import ../../nix/lib/refined.nix { inherit lib; };

  # --- Test 1: Auto-extracted refinements from inline type declarations ---

  schemaWithRefinedTypes = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption { };
        config.schema.service = {
          options.port = lib.mkOption {
            type = refinedLib.types.refined lib.types.int {
              check = v: v > 0 && v < 65536;
              message = "must be valid TCP port";
            };
          };
          options.name = lib.mkOption { type = lib.types.str; };
        };
      }
    ];
  };

  schemaR = schemaWithRefinedTypes.config.schema;

  # mkInstanceRegistry without explicit refinements — should auto-extract
  autoRegistry = mkInstanceRegistry schemaR "service" { };

  validEval = lib.evalModules {
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

  invalidEval = lib.evalModules {
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

  monitorable = schemaLib.mkMixin {
    requires = [ "port" ];
    provides = [ "metrics_port" ];
    define = parent: {
      metrics_port = lib.mkOption {
        type = lib.types.int;
        default = (R.select parent "port").default or 9090;
      };
    };
  };

  schemaWithMixins = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption {
          mixins = [ monitorable ];
          baseModule = {
            port = lib.mkOption {
              type = lib.types.int;
              default = 8080;
            };
            hostname = lib.mkOption { type = lib.types.str; };
          };
        };
        config.schema.service = { };
      }
    ];
  };

  schemaM = schemaWithMixins.config.schema;
  mixinRegistry = mkInstanceRegistry schemaM "service" { };

  mixinEval = lib.evalModules {
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
  auto-integration.test-auto-refinement-valid = {
    expr = validEval.config.services.web.port;
    expected = 8080;
  };

  # Auto-extracted refinements: invalid value throws
  auto-integration.test-auto-refinement-invalid-throws = {
    expr = builtins.tryEval (builtins.deepSeq invalidEval.config.services { });
    expected = {
      success = false;
      value = false;
    };
  };

  # Auto-extracted refinements: schema kind has refinements attr
  auto-integration.test-schema-kind-has-refinements = {
    expr = schemaR.service ? refinements;
    expected = true;
  };

  # Auto-extracted refinements: refinements map has the refined field
  auto-integration.test-refinements-has-port = {
    expr = schemaR.service.refinements ? port;
    expected = true;
  };

  # Auto-applied mixins: mixin-provided option exists
  auto-integration.test-auto-mixin-option-exists = {
    expr = mixinEval.config.services.web ? metrics_port;
    expected = true;
  };

  # Auto-applied mixins: base fields preserved
  auto-integration.test-auto-mixin-base-preserved = {
    expr = mixinEval.config.services.web.hostname;
    expected = "localhost";
  };
}
