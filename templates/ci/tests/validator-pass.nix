{ lib, schemaLib, ... }:
let
  eval = lib.evalModules {
    modules = [
      {
        options.schema = schemaLib.mkSchemaOption { };
        options.hosts = schemaLib.mkInstanceRegistry eval.config.schema "host" { };
        config.schema.host = {
          options.addr = lib.mkOption { type = lib.types.str; };
          options.role = lib.mkOption { type = lib.types.str; };
          validators = [
            (schemaLib.mkValidator "has-addr" ({ addr, ... }: addr != "") "addr must not be empty")
          ];
        };
        config.hosts.igloo = {
          addr = "10.0.1.1";
          role = "web";
        };
      }
    ];
  };
  result = schemaLib.validateInstances eval.config.schema "host" eval.config.hosts;
in
{
  "validator-pass".test-right-returned = {
    expr = result ? right;
    expected = true;
  };
}
