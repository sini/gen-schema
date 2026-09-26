{
  lib,
  genSchema,
  genMerge,
  genAlgebra,
  ...
}:
let
  inherit (genSchema) evalSchema mkInstanceRegistry;
  inherit (genSchema) declarationOf;

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
                  type = declarationOf eval.config.hosts;
                };
              }
            )
          ];
        };
        config.hosts.igloo = {
          addr = "10.0.1.1";
        };
        config.services.badref = {
          host = "nonexistent";
          port = 99;
        };
      }
    ];
  };
in
{
  flake.tests.ref-invalid = {
    test-bad-ref-throws = {
      expr = !(builtins.tryEval (builtins.deepSeq eval.config.services.badref.host.addr "ok")).success;
      expected = true;
    };
  };
}
