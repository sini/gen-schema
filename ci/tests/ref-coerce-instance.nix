{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) evalSchema mkInstanceRegistry declarationOf;

  schema = evalSchema {
    modules = [
      {
        config.schema.host = {
          options.addr = genMerge.mkOption { type = genMerge.types.str; };
        };
        config.schema.service = {
          options.port = genMerge.mkOption { type = genMerge.types.int; };
          options.host = genMerge.mkOption { type = declarationOf "host"; };
        };
        config.schema.link = {
          options.label = genMerge.mkOption { type = genMerge.types.str; };
        };
      }
    ];
  };

  # Test both deferred and direct modes with instance-value coercion.
  eval = genMerge.evalModuleTree {
    modules = [
      {
        options.hosts = mkInstanceRegistry schema.host { };

        # Deferred mode with instance value
        options.services = mkInstanceRegistry schema.service {
          refs.host = eval.config.hosts;
        };

        # Direct mode with instance value
        options.links = mkInstanceRegistry schema.link {
          extraModules = [
            (
              { ... }:
              {
                options.target = genMerge.mkOption {
                  type = declarationOf eval.config.hosts;
                };
              }
            )
          ];
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
