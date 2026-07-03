{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) mkSchemaOption mkInstanceRegistry ref;

  throwsOnInvalidKey =
    let
      result = builtins.tryEval (
        let
          eval = genMerge.evalModuleTree {
            modules = [
              {
                options.schema = mkSchemaOption { };
                options.hosts = mkInstanceRegistry eval.config.schema.host { };
                options.services = mkInstanceRegistry eval.config.schema.service {
                  refs.host = eval.config.hosts;
                };
                config.schema.host = {
                  options.addr = genMerge.mkOption { type = genMerge.types.str; };
                };
                config.schema.service = {
                  options.host = genMerge.mkOption { type = ref "host"; };
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
