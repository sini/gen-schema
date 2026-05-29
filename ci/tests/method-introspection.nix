{ lib, genSchema, ... }:
let
  inherit (genSchema) mkSchemaOption schemaFn;

  eval = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption { };
        config.schema.host = {
          options.name = lib.mkOption { type = lib.types.str; };
          methods.greet = schemaFn "Greet" lib.types.str ({ name, ... }: "hi ${name}");
        };
      }
    ];
  };

  hostKind = eval.config.schema.host;
in
{
  flake.tests.method-intro.test-method-in-option-names = {
    expr = hostKind.options ? greet;
    expected = true;
  };
}
