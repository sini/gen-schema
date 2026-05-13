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
            (schemaLib.mkValidator "has-addr" ({ addr, ... }: addr != "") "addr must not be empty")
          ];
        };
        config.hosts.good-a = {
          addr = "10.0.1.1";
        };
        config.hosts.good-b = {
          addr = "10.0.1.2";
        };
        config.hosts.bad-a = {
          addr = "";
        };
        config.hosts.bad-b = {
          addr = "";
        };
      }
    ];
  };
  result = schemaLib.validateInstances eval.config.schema "host" eval.config.hosts;
  failedNames = lib.sort (a: b: a < b) (map (f: f.name) result.left);
in
{
  "validator-instances".test-left-returned = {
    expr = result ? left;
    expected = true;
  };
  "validator-instances".test-only-failing-instances = {
    expr = failedNames;
    expected = [
      "bad-a"
      "bad-b"
    ];
  };
  "validator-instances".test-error-count = {
    expr = lib.length result.left;
    expected = 2;
  };
}
