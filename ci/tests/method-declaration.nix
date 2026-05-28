{ lib, schemaLib, ... }:
let
  inherit (schemaLib) mkSchemaOption schemaFn;

  eval = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption { };
        config.schema.host = {
          options.name = lib.mkOption { type = lib.types.str; };
          options.addr = lib.mkOption { type = lib.types.str; };
          methods.greeting = schemaFn "Greeting message" lib.types.str (
            { name, addr, ... }: "Hello from ${name} at ${addr}"
          );
        };
      }
    ];
  };

  hostKind = eval.config.schema.host;

  instance = lib.evalModules {
    modules = [
      hostKind
      {
        config.name = "igloo";
        config.addr = "10.0.1.1";
      }
    ];
  };
in
{
  flake.tests.method-decl.test-greeting-value = {
    expr = instance.config.greeting;
    expected = "Hello from igloo at 10.0.1.1";
  };
  flake.tests.method-decl.test-greeting-option-is-readonly = {
    expr = instance.options.greeting.readOnly;
    expected = true;
  };
}
