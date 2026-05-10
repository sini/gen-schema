{ lib, schemaLib, ... }:
let
  inherit (schemaLib) mkSchema;

  # Schema with strict = false — undeclared keys should be accepted
  schemaEval = lib.evalModules {
    modules = [
      {
        options.schema = mkSchema { strict = false; };
        config.schema.host = {
          options.name = lib.mkOption { type = lib.types.str; };
        };
      }
    ];
  };

  hostKind = schemaEval.config.schema.host;

  # Instance with an undeclared key — should not throw with strict = false
  instance = lib.evalModules {
    modules = [
      hostKind
      {
        config.name = "igloo";
        config.undeclaredKey = "should work";
      }
    ];
  };

  result = builtins.tryEval (builtins.deepSeq instance.config instance.config);
in
{
  strict-toggle.test-non-strict-accepts-undeclared = {
    expr = result.success;
    expected = true;
  };
  strict-toggle.test-non-strict-declared-key-works = {
    expr = result.value.name;
    expected = "igloo";
  };
}
