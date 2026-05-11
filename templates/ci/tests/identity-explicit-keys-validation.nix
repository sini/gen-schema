{ lib, schemaLib, ... }:
let
  inherit (schemaLib._internal) identityModule;

  # Explicit key naming a nonexistent option
  evalMissing = lib.evalModules {
    modules = [
      (identityModule "host")
      { options.name = lib.mkOption { type = lib.types.str; }; }
      {
        config.name = "igloo";
        config._identity.keys = [ "name" "nonexistent" ];
      }
    ];
  };
  missingResult = builtins.tryEval (builtins.deepSeq evalMissing.config.id_hash evalMissing.config.id_hash);

  # Explicit key naming a non-primitive option
  evalNonPrimitive = lib.evalModules {
    modules = [
      (identityModule "host")
      { options.name = lib.mkOption { type = lib.types.str; }; }
      { options.tags = lib.mkOption { type = lib.types.listOf lib.types.str; default = []; }; }
      {
        config.name = "igloo";
        config._identity.keys = [ "name" "tags" ];
      }
    ];
  };
  nonPrimitiveResult = builtins.tryEval (builtins.deepSeq evalNonPrimitive.config.id_hash evalNonPrimitive.config.id_hash);
in
{
  "identity-validate".test-explicit-missing-key-throws = {
    expr = missingResult.success;
    expected = false;
  };
  "identity-validate".test-explicit-non-primitive-key-throws = {
    expr = nonPrimitiveResult.success;
    expected = false;
  };
}
