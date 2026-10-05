{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  schema = genSchema.evalSchema { } [
    {
      config.schema.host = {
        options.addr = genMerge.mkOption { type = genMerge.types.str; };
      };
    }
  ];

  eval = genMerge.evalModuleTree { } [
    {
      options.hosts = genSchema.mkInstanceRegistry {
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
      } schema.host;
      config.hosts.igloo.addr = "10.0.1.1";
    }
  ];
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
