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
          options.host = genMerge.mkOption { type = declarationOf "host"; };
        };
      }
    ];
  };

  throwsOnInvalidKey =
    let
      result = builtins.tryEval (
        let
          eval = genMerge.evalModuleTree {
            modules = [
              {
                options.hosts = mkInstanceRegistry schema.host { };
                options.services = mkInstanceRegistry schema.service {
                  refs.host = eval.config.hosts;
                };
                config.hosts.igloo = {
                  addr = "10.0.1.1";
                };
                config.services.nginx = {
                  host = "nonexistent";
                };
              }
            ];
          };
        in
        eval.config.services.nginx.host.addr
      );
    in
    !result.success;
in
{
  flake.tests.ref-invalid-key = {
    test-invalid-key-throws = {
      expr = throwsOnInvalidKey;
      expected = true;
    };
  };
}
