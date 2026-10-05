{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) mkSchemaOption schemaFn;

  eval = genMerge.evalModuleTree { } [
    {
      options.schema = mkSchemaOption { };
      config.schema.host = {
        options.name = genMerge.mkOption { type = genMerge.types.str; };
        methods.broken = schemaFn {
          description = "Broken method";
          type = genMerge.types.str;
          fn = { nonexistent, ... }: "should fail";
        };
      };
    }
  ];

  hostKind = eval.config.schema.host;

  instance = genMerge.evalModuleTree { } [
    hostKind
    { config.name = "igloo"; }
  ];

  result = builtins.tryEval (builtins.deepSeq instance.config.broken instance.config.broken);
in
{
  flake.tests.method-bad.test-bad-arg-throws = {
    expr = result.success;
    expected = false;
  };
}
