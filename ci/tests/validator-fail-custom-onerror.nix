{
  lib,
  genSchema,
  genMerge,
  genAlgebra,
  ...
}:
let
  eval = genMerge.evalModuleTree {
    modules = [
      {
        options.schema = genSchema.mkSchemaOption { };
        options.hosts = genSchema.mkInstanceRegistry eval.config.schema.host {
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
        };
        config.schema.host = {
          options.addr = genMerge.mkOption { type = genMerge.types.str; };
          validators = [
            (genSchema.mkValidator "always-fail" (_: false) "always fails")
          ];
        };
        config.hosts.igloo.addr = "10.0.1.1";
      }
    ];
  };
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
