# Tests for auto-extraction of refinements from types and auto-application of mixins.
# These verify the spec's promise: refinements co-located with types are extracted
# automatically, and mkSchemaEntryType { mixins = [...] } applies them without manual
# applyMixin + emitModule calls.
{
  lib,
  genSchema,
  genMerge,
  genAlgebra,
  genIdentity,
  ...
}:
let
  inherit (genSchema) mkSchemaOption mkSchemaEntryType mkInstanceRegistry;
  R = genAlgebra.record;
  refinedLib = import ../../lib/refined.nix {
    merge = genMerge;
    identity = genIdentity;
  };

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

  # --- den-hoag-zijk1: the refinement plane is a projection of the option plane ---
  # Wherever the engine collects a refined option — `imports`, `baseModule`, a function module, a
  # kind with mixins — its contract lands and is enforced. Before, a second syntactic reader of
  # the raw defs saw only an inline `options` key, and 70000 passed a `tcpPort` contract.

  portOpt = genMerge.mkOption {
    type = genSchema.refined genMerge.types.int genSchema.refinements.tcpPort;
  };
  tcpMsg = [ "must be a valid TCP port (1-65535)" ];
  hostKind =
    args: decl:
    (genMerge.evalModuleTree {
      modules = [
        { options.schema = mkSchemaOption args; }
        { config.schema.host = decl; }
      ];
    }).config.schema.host;
  messages = k: builtins.mapAttrs (_: map (r: r.message)) k.refinements;
  portAccepted =
    args: decl: port:
    builtins.tryEval
      (genMerge.evalModuleTree {
        modules = [
          { options.hosts = mkInstanceRegistry (hostKind args decl) { }; }
          { config.hosts.a.myPort = port; }
        ];
      }).config.hosts.a.myPort;
  imported = {
    imports = [ { options.myPort = portOpt; } ];
  };
  moduleStyle = {
    options.myPort = portOpt;
  };
  mixinArgs = {
    mixins = [ monitorable ];
    baseModule.port = genMerge.mkOption {
      type = genMerge.types.int;
      default = 8080;
    };
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

  flake.tests.reverse-half-read = {
    test-imported-option-lands-its-refinement = {
      expr = messages (hostKind { } imported);
      expected.myPort = tcpMsg;
    };
    test-baseModule-option-lands-its-refinement = {
      expr = messages (hostKind { baseModule.options.myPort = portOpt; } { });
      expected.myPort = tcpMsg;
    };
    test-function-module-option-lands-its-refinement = {
      expr = messages (hostKind { } ({ ... }: moduleStyle));
      expected.myPort = tcpMsg;
    };
    test-imported-option-refuses-out-of-contract = {
      expr = (portAccepted { } imported 70000).success;
      expected = false;
    };
    # CONTROL: the in-contract value on the same shape is accepted, so the refusal above is the
    # contract and not a shape that refuses everything.
    test-imported-option-accepts-in-contract = {
      expr = portAccepted { } imported 8080;
      expected = {
        success = true;
        value = 8080;
      };
    };
    # CONTROL: the module-style shape, which both readers always saw.
    test-module-style-control = {
      expr = {
        messages = messages (hostKind { } moduleStyle);
        accepted = (portAccepted { } moduleStyle 70000).success;
      };
      expected = {
        messages.myPort = tcpMsg;
        accepted = false;
      };
    };
    # The mixin branch: a contract declared in the kind entry itself, beside the bridge's record.
    test-mixin-kind-entry-option-refuses-out-of-contract = {
      expr = (portAccepted mixinArgs moduleStyle 70000).success;
      expected = false;
    };
    test-mixin-kind-entry-option-accepts-in-contract = {
      expr = portAccepted mixinArgs moduleStyle 8080;
      expected = {
        success = true;
        value = 8080;
      };
    };
    # An unstructured top-level `mkOption` is config to the engine, so it lands neither plane.
    test-flat-unstructured-lands-no-refinement = {
      expr = builtins.attrNames (hostKind { } { myPort = portOpt; }).refinements;
      expected = [ ];
    };
  };
}
