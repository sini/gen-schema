{ lib, schemaLib, ... }:
let
  inherit (schemaLib) mkStrictModule;
  eval = lib.evalModules {
    modules = [
      (mkStrictModule "host")
      { options.name = lib.mkOption { type = lib.types.str; }; }
      { config.name = "igloo"; config.badKey = "oops"; }
    ];
  };
  threw = builtins.tryEval (builtins.deepSeq eval.config eval.config);
in {
  strict.test-undeclared-key-throws = {
    expr = threw.success;
    expected = false;
  };
  strict.test-declared-key-works = {
    expr = (lib.evalModules {
      modules = [
        (mkStrictModule "host")
        { options.name = lib.mkOption { type = lib.types.str; }; }
        { config.name = "igloo"; }
      ];
    }).config.name;
    expected = "igloo";
  };
}
