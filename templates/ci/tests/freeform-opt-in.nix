{ lib, schemaLib, ... }:
let
  inherit (schemaLib._internal) mkStrictModule;
  eval = lib.evalModules {
    modules = [
      (mkStrictModule "host")
      { _module.freeformType = lib.types.attrsOf lib.types.anything; }
      { options.name = lib.mkOption { type = lib.types.str; }; }
      { config.name = "igloo"; config.extra = "allowed"; }
    ];
  };
in {
  "strict.freeform-opt-in".test-freeform-opt-in = {
    expr = eval.config.extra;
    expected = "allowed";
  };
}
