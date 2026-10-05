{
  lib,
  genSchema,
  genMerge,
  genAlgebra,
  ...
}:
let
  schema = genSchema.evalSchema { } [
    {
      config.schema.host = {
        options.addr = genMerge.mkOption { type = genMerge.types.str; };
        validators = [
          (genSchema.mkValidator {
            name = "always-fail";
            pred = _: false;
            message = "always fails";
          })
        ];
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
          derive = instances: { right = lib.mapAttrs (name: _: { tag = "derived-${name}"; }) instances; };
          onError = _: { };
        };
      } schema.host;
      config.hosts.igloo.addr = "10.0.1.1";
    }
  ];
in
{
  flake.tests."validator-custom-error" = {
    test-no-throw = {
      expr =
        (builtins.tryEval (builtins.deepSeq eval.config.hosts.igloo.addr eval.config.hosts.igloo.addr))
        .success;
      expected = true;
    };
    # After recovery, derive still runs — tag gets the derived value
    test-derive-runs-after-recovery = {
      expr = eval.config.hosts.igloo.tag;
      expected = "derived-igloo";
    };
  };
}
