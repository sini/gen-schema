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
        config.hosts.igloo.addr = "10.0.1.1";
      }
    ];
  };
in
{
  "derive-none" = {
    test-basic-access = {
      expr = eval.config.hosts.igloo.addr;
      expected = "10.0.1.1";
    };
    test-name = {
      expr = eval.config.hosts.igloo.name;
      expected = "igloo";
    };
  };
}
