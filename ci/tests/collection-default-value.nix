{ lib, schemaLib, ... }:
let
  inherit (schemaLib) mkSchemaOption;

  eval = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption {
          collections.includes = {
            default = [ ];
          };
        };
        config.schema.host = {
          options.name = lib.mkOption { type = lib.types.str; };
        };
      }
    ];
  };
in
{
  flake.tests.collection-default.test-empty-default = {
    expr = eval.config.schema.host.includes;
    expected = [ ];
  };
}
