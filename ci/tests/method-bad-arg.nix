{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) mkSchemaOption schemaFn;

  eval = genMerge.evalModuleTree {
    modules = [
      {
        options.schema = mkSchemaOption { };
        config.schema.host = {
          options.name = genMerge.mkOption { type = genMerge.types.str; };
          methods.broken = schemaFn "Broken method" genMerge.types.str ({ nonexistent, ... }: "should fail");
        };
      }
    ];
  };

  hostKind = eval.config.schema.host;

  instance = genMerge.evalModuleTree {
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
