{
  lib,
  schemaLib,
  ...
}:
let
  inherit (schemaLib) mkSchemaOption mkInstanceRegistry ref;

  # Test both deferred and direct modes with instance-value coercion.
  eval = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption { };
        options.hosts = mkInstanceRegistry eval.config.schema.host { };

        # Deferred mode with instance value
        options.services = mkInstanceRegistry eval.config.schema.service {
          refs.host = eval.config.hosts;
        };

        # Direct mode with instance value
        options.links = mkInstanceRegistry eval.config.schema.link {
          extraModules = [
            (
              { ... }:
              {
                options.target = lib.mkOption {
                  type = ref eval.config.hosts;
                };
              }
            )
          ];
        };

        config.schema.host = {
          options.addr = lib.mkOption { type = lib.types.str; };
        };
        config.schema.service = {
          options.port = lib.mkOption { type = lib.types.int; };
          options.host = lib.mkOption { type = ref "host"; };
        };
        config.schema.link = {
          options.label = lib.mkOption { type = lib.types.str; };
        };
        config.hosts.igloo = {
          addr = "10.0.1.1";
        };

        # Assign instance values instead of string keys
        config.services.nginx = {
          host = eval.config.hosts.igloo;
          port = 80;
        };
        config.links.main = {
          target = eval.config.hosts.igloo;
          label = "primary";
        };
      }
    ];
  };
in
{
  flake.tests.ref-coerce-instance = {
    test-deferred-instance-coercion = {
      expr = eval.config.services.nginx.host.addr;
      expected = "10.0.1.1";
    };
    test-direct-instance-coercion = {
      expr = eval.config.links.main.target.addr;
      expected = "10.0.1.1";
    };
  };
}
