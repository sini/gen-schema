{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) mkStrictModule;
  eval = genMerge.evalModuleTree {
    modules = [
      (mkStrictModule "host")
      { options.name = genMerge.mkOption { type = genMerge.types.str; }; }
      {
        config.name = "igloo";
        config.badKey = "oops";
      }
    ];
  };
  threw = builtins.tryEval (builtins.deepSeq eval.config eval.config);
in
{
  flake.tests.strict-module.test-undeclared-key-throws = {
    expr = threw.success;
    expected = false;
  };
  flake.tests.strict-module.test-declared-key-works = {
    expr =
      (genMerge.evalModuleTree {
        modules = [
          (mkStrictModule "host")
          { options.name = genMerge.mkOption { type = genMerge.types.str; }; }
          { config.name = "igloo"; }
        ];
      }).config.name;
    expected = "igloo";
  };
}
