{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  schema = genSchema.evalSchema {
    modules = [
      {
        config.schema.host = {
          options.addr = genMerge.mkOption { type = genMerge.types.str; };
        };
      }
    ];
  };

  eval = genMerge.evalModuleTree {
    modules = [
      {
        options.hosts = genSchema.mkInstanceRegistry schema.host {
          extraModules = [
            {
              options.tag = genMerge.mkOption {
                type = genMerge.types.str;
                default = "fallback";
                internal = true;
              };
            }
          ];
          deriveEither = {
            derive = _instances: { left = "error"; };
            onError = _: { };
          };
        };
        config.hosts.igloo.addr = "10.0.1.1";
      }
    ];
  };
in
{
  flake.tests."derive-either-custom" = {
    test-no-throw = {
      expr =
        (builtins.tryEval (builtins.deepSeq eval.config.hosts.igloo.addr eval.config.hosts.igloo.addr))
        .success;
      expected = true;
    };
    test-fallback-tag = {
      expr = eval.config.hosts.igloo.tag;
      expected = "fallback";
    };
  };
}
