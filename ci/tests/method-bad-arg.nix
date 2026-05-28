{ lib, schemaLib, ... }:
let
  inherit (schemaLib) mkSchemaOption schemaFn;

  eval = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption { };
        config.schema.host = {
          options.name = lib.mkOption { type = lib.types.str; };
          methods.broken = schemaFn "Broken method" lib.types.str ({ nonexistent, ... }: "should fail");
        };
      }
    ];
  };

  hostKind = eval.config.schema.host;

  instance = lib.evalModules {
    modules = [
      hostKind
      { config.name = "igloo"; }
    ];
  };

  result = builtins.tryEval (builtins.deepSeq instance.config.broken instance.config.broken);
in
{
  flake.tests.method-bad.test-bad-arg-throws = {
    expr = result.success;
    expected = false;
  };
}
