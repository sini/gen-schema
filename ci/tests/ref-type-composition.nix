{
  lib,
  genSchema,
  genMerge,
  genAlgebra,
  ...
}:
let
  inherit (genSchema) evalSchema mkInstanceRegistry;
  inherit (genSchema) ref;

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

  # Two separate modules: one defines hosts, another defines services with refs
  eval = genMerge.evalModuleTree {
    modules = [
      # Module 1: hosts
      {
        options.hosts = mkInstanceRegistry schema.host { };
        config.hosts.igloo = {
          addr = "10.0.1.1";
        };
      }
      # Module 2: services with ref to hosts
      {
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
        config.services.nginx = {
          host = "igloo";
          port = 80;
        };
      }
    ];
  };
in
{
  flake.tests.ref-compose = {
    test-cross-module-ref-resolves = {
      expr = eval.config.services.nginx.host.addr;
      expected = "10.0.1.1";
    };
    test-cross-module-ref-name = {
      expr = eval.config.services.nginx.host.name;
      expected = "igloo";
    };
  };
}
