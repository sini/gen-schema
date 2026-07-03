{
  lib,
  genSchema,
  genMerge,
  genAlgebra,
  ...
}:
let
  inherit (genSchema) mkSchemaOption mkInstanceRegistry;
  inherit (genSchema) ref;

  eval = genMerge.evalModuleTree {
    modules = [
      {
        options.schema = mkSchemaOption { };
        options.hosts = mkInstanceRegistry eval.config.schema.host { };
        options.services = mkInstanceRegistry eval.config.schema.service {
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
        config.schema.host = {
          options.addr = genMerge.mkOption { type = genMerge.types.str; };
        };
        config.schema.service = {
          options.port = genMerge.mkOption { type = genMerge.types.int; };
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
