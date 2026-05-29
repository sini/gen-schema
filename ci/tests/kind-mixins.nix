{
  lib,
  genSchema,
  genAlgebra,
  ...
}:
let
  R = genAlgebra.record;
  record = R;
  mixinLib = import ../../nix/lib/mixin.nix { inherit lib record; };
  refinedLib = import ../../nix/lib/refined.nix { inherit lib; };
  bridgeLib = import ../../nix/lib/bridge.nix {
    inherit lib record;
    inherit (refinedLib) isRefined getRefinements;
  };
  inherit (mixinLib) mkMixin composeMixins applyMixin;
  inherit (bridgeLib) emitModule;
  inherit (genSchema) mkSchemaOption mkInstanceRegistry;

  # A mixin that adds a metrics_port option
  monitorable = mkMixin {
    requires = [ "port" ];
    provides = [ "metrics_port" ];
    define = _parent: {
      metrics_port = lib.mkOption {
        type = lib.types.int;
        default = 9090;
        description = "Port for metrics endpoint";
      };
    };
  };

  # Build a schema kind manually using the mixin workflow
  baseRecord = R.fromAttrs {
    port = lib.mkOption { type = lib.types.int; };
    hostname = lib.mkOption { type = lib.types.str; };
  };

  withMixin = applyMixin monitorable baseRecord "service";
  emitted = emitModule [ ] withMixin;

  # Use the emitted module in a schema
  schemaEval = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption { };
        config.schema.service = emitted.module;
      }
    ];
  };

  schema = schemaEval.config.schema;

  # Create instances
  registry = mkInstanceRegistry schema.service { };
  eval = lib.evalModules {
    modules = [
      {
        options.services = registry;
        config.services.web = {
          port = 8080;
          hostname = "localhost";
        };
      }
    ];
  };

  # Test that mkSchemaEntryType stores mixins
  entryWithMixins = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption { mixins = [ monitorable ]; };
        config.schema.svc = {
          port = lib.mkOption { type = lib.types.int; };
        };
      }
    ];
  };
in
{
  flake.tests.kind-mixins.test-mixin-adds-option = {
    expr = eval.config.services.web ? metrics_port;
    expected = true;
  };

  flake.tests.kind-mixins.test-mixin-default-value = {
    expr = eval.config.services.web.metrics_port;
    expected = 9090;
  };

  flake.tests.kind-mixins.test-base-fields-preserved = {
    expr = eval.config.services.web.hostname;
    expected = "localhost";
  };

  flake.tests.kind-mixins.test-base-port-preserved = {
    expr = eval.config.services.web.port;
    expected = 8080;
  };

  flake.tests.kind-mixins.test-entry-type-stores-mixins = {
    expr = builtins.length entryWithMixins.config.schema.svc.mixins;
    expected = 1;
  };

  flake.tests.kind-mixins.test-entry-type-empty-mixins-default = {
    expr =
      let
        e = lib.evalModules {
          modules = [
            {
              options.schema = mkSchemaOption { };
              config.schema.basic = {
                name = lib.mkOption { type = lib.types.str; };
              };
            }
          ];
        };
      in
      e.config.schema.basic.mixins;
    expected = [ ];
  };

  # Export presence tests
  flake.tests.kind-mixins.test-exports-mkMixin = {
    expr = genSchema ? mkMixin;
    expected = true;
  };

  flake.tests.kind-mixins.test-exports-composeMixins = {
    expr = genSchema ? composeMixins;
    expected = true;
  };

  flake.tests.kind-mixins.test-exports-beta = {
    expr = genSchema ? beta;
    expected = true;
  };

  flake.tests.kind-mixins.test-exports-applyMixin = {
    expr = genSchema ? applyMixin;
    expected = true;
  };

  flake.tests.kind-mixins.test-exports-blame = {
    expr = genSchema ? blame;
    expected = true;
  };

  flake.tests.kind-mixins.test-exports-refined = {
    expr = genSchema ? refined;
    expected = true;
  };

  flake.tests.kind-mixins.test-exports-emitModule = {
    expr = genSchema ? emitModule;
    expected = true;
  };

  flake.tests.kind-mixins.test-exports-refinements = {
    expr = genSchema ? refinements;
    expected = true;
  };

  flake.tests.kind-mixins.test-exports-mkFieldValidator = {
    expr = genSchema ? mkFieldValidator;
    expected = true;
  };
}
