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
            (schemaLib.mkValidator "valid-role" (
              { role, ... }:
              lib.elem role [
                "web"
                "db"
                "worker"
              ]
            ) "role must be web, db, or worker")
          ];
        };
        config.hosts.bad = {
          addr = "";
          role = "invalid";
        };
        config.hosts.good = {
          addr = "10.0.1.1";
          role = "web";
        };
      }
    ];
  };
  result = schemaLib.validateInstances eval.config.schema "host" eval.config.hosts;
in
{
  "validator-multi".test-accumulates-errors = {
    expr = lib.length result.left;
    expected = 2;
  };
  "validator-multi".test-only-bad-instance = {
    expr = lib.all (f: f.name == "bad") result.left;
    expected = true;
  };
}
