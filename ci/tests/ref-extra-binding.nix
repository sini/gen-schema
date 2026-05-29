{
  lib,
  genSchema,
  ...
}:
let
  inherit (genSchema) mkSchemaOption mkInstanceRegistry ref;

  throwsOnExtraBinding =
    let
      result = builtins.tryEval (
        let
          eval = lib.evalModules {
            modules = [
              {
                options.schema = mkSchemaOption { };
                options.hosts = mkInstanceRegistry eval.config.schema.host { };
                options.services = mkInstanceRegistry eval.config.schema.service {
                  refs.host = eval.config.hosts;
                  refs.network = eval.config.hosts; # no ref field named "network"
                };
                config.schema.host = {
                  options.addr = lib.mkOption { type = lib.types.str; };
                };
                config.schema.service = {
                  options.host = lib.mkOption { type = ref "host"; };
                };
                config.hosts.igloo = {
                  addr = "10.0.1.1";
                };
                config.services.nginx = {
                  host = "igloo";
                };
              }
            ];
          };
        in
        builtins.attrNames eval.config.services
      );
    in
    !result.success;
in
{
  flake.tests.ref-extra-binding = {
    test-extra-binding-throws = {
      expr = throwsOnExtraBinding;
      expected = true;
    };
  };
}
