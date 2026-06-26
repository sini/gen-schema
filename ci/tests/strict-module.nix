{ lib, genSchema, ... }:
let
  inherit (genSchema) mkStrictModule;
  eval = lib.evalModules {
    modules = [
      (mkStrictModule "host")
      { options.name = lib.mkOption { type = lib.types.str; }; }
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
      (lib.evalModules {
        modules = [
          (mkStrictModule "host")
          { options.name = lib.mkOption { type = lib.types.str; }; }
          { config.name = "igloo"; }
        ];
      }).config.name;
    expected = "igloo";
  };
}
