{ lib, schemaLib, ... }:
let
  eval = lib.evalModules {
    modules = [
      {
        options.schema = schemaLib.mkSchemaOption { };
        options.hosts = schemaLib.mkInstanceRegistry eval.config.schema "host" { };
        config.schema.host = {
          options.addr = lib.mkOption { type = lib.types.str; };
          validators = [
            (schemaLib.mkValidator "has-addr" ({ addr, ... }: addr != "") "need addr")
          ];
        };
        config.hosts.good = {
          addr = "10.0.1.1";
        };
        config.hosts.bad = {
          addr = "";
        };
      }
    ];
  };
  result = schemaLib.validateInstances eval.config.schema "host" eval.config.hosts;
in
{
  "validate-standalone".test-returns-either = {
    expr = result ? left || result ? right;
    expected = true;
  };
  "validate-standalone".test-has-errors = {
    expr = result ? left;
    expected = true;
  };
  "validate-standalone".test-does-not-throw = {
    expr = (builtins.tryEval result).success;
    expected = true;
  };
}
