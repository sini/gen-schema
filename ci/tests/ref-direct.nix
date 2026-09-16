{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) evalSchema mkInstanceRegistry ref;

  schema = evalSchema {
    modules = [
      {
        config.schema.host = {
          options.addr = genMerge.mkOption { type = genMerge.types.str; };
        };
        config.schema.service = {
          options.port = genMerge.mkOption { type = genMerge.types.int; };
        };
      }
    ];
  };

  eval = genMerge.evalModuleTree {
    modules = [
      {
        options.hosts = mkInstanceRegistry schema.host { };
        options.services = mkInstanceRegistry schema.service {
          extraModules = [
            (
              { ... }:
              {
                options.host = genMerge.mkOption {
                  type = ref eval.config.hosts;
                };
              }
            )
          ];
        };
        config.hosts.igloo = {
          addr = "10.0.1.1";
        };
        config.services.nginx = {
          host = "igloo";
          port = 80;
        };
      }
    ];
  };

  inherit (eval.config.services) nginx;
in
{
  flake.tests.ref-direct = {
    test-direct-ref-resolves-addr = {
      expr = nginx.host.addr;
      expected = "10.0.1.1";
    };
    test-direct-ref-resolves-name = {
      expr = nginx.host.name;
      expected = "igloo";
    };
  };
}
