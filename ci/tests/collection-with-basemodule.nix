# baseModule options coexist correctly with collection extraction.
{ lib, schemaLib, ... }:
let
  eval = lib.evalModules {
    modules = [
      {
        options.schema = schemaLib.mkSchemaOption {
          baseModule.options.description = lib.mkOption {
            type = lib.types.str;
            default = "";
          };
          collections.tags = {
            default = [ ];
          };
        };
        options.hosts = schemaLib.mkInstanceRegistry eval.config.schema "host" { };
        config.schema.host = {
          tags = [
            "web"
            "prod"
          ];
          options.addr = lib.mkOption { type = lib.types.str; };
        };
        config.hosts.igloo.addr = "10.0.1.1";
      }
    ];
  };
in
{
  flake.tests."collection-base".test-base-option-on-instance = {
    expr = eval.config.hosts.igloo.description;
    expected = "";
  };
  flake.tests."collection-base".test-collection-on-kind = {
    expr = eval.config.schema.host.tags;
    expected = [
      "web"
      "prod"
    ];
  };
  flake.tests."collection-base".test-both-coexist = {
    expr = eval.config.hosts.igloo.addr;
    expected = "10.0.1.1";
  };
}
