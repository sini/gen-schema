{ lib, schemaLib, ... }:
let
  inherit (schemaLib) mkSchemaOption schemaFn;

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

  meta = eval.config.schema._meta.kindMeta "host";
in
{
  method-intro.test-method-in-option-names = {
    expr = builtins.elem "greet" meta.optionNames;
    expected = true;
  };
}
