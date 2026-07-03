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
          options.addr = genMerge.mkOption { type = genMerge.types.str; };
          methods.greeting = schemaFn "Greeting message" genMerge.types.str (
            { name, addr, ... }: "Hello from ${name} at ${addr}"
          );
        };
      }
    ];
  };

  hostKind = eval.config.schema.host;

  instance = genMerge.evalModuleTree {
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
