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
        methods.greet = schemaFn {
          description = "Greet";
          type = genMerge.types.str;
          fn = { name, ... }: "hi ${name}";
        };
      };
    }
  ];

  hostKind = eval.config.schema.host;
in
{
  flake.tests.method-intro.test-method-in-option-names = {
    expr = hostKind.options ? greet;
    expected = true;
  };
}
