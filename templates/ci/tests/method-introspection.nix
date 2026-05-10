{ lib, schemaLib, ... }:
let
  inherit (schemaLib) mkSchema schemaFn;

  eval = lib.evalModules {
    modules = [
      {
        options.schema = mkSchema { };
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
