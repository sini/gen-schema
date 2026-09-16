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
          options.host = genMerge.mkOption { type = ref "host"; };
        };
      }
    ];
  };

  throwsOnExtraBinding =
    let
      result = builtins.tryEval (
        let
          eval = genMerge.evalModuleTree {
            modules = [
              {
                options.hosts = mkInstanceRegistry schema.host { };
                options.services = mkInstanceRegistry schema.service {
                  refs.host = eval.config.hosts;
                  refs.network = eval.config.hosts; # no ref field named "network"
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
