{ lib, schemaLib, ... }:
let
  eval = lib.evalModules {
    modules = [
      {
        options.schema = schemaLib.mkSchemaOption { };
        options.hosts = schemaLib.mkInstanceRegistry eval.config.schema "host" { };
        config.schema.host = {
          options.addr = lib.mkOption { type = lib.types.str; };
        };
        config.hosts.igloo = {
          addr = "10.0.1.1";
        };
      }
    ];
  };
  result = schemaLib.validateInstances eval.config.schema "host" eval.config.hosts;
in
{
  "validator-none".test-right-when-no-validators = {
    expr = result ? right;
    expected = true;
  };
  "validator-none".test-instances-pass-through = {
    expr = result.right.igloo.addr;
    expected = "10.0.1.1";
  };
}
