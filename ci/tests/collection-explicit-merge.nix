{ lib, schemaLib, ... }:
let
  inherit (schemaLib) mkSchemaOption;

  eval = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption {
          collections.priority = {
            default = 0;
            merge = _acc: val: val;
          };
        };
        config.schema.host = {
          options.name = lib.mkOption { type = lib.types.str; };
          priority = 10;
        };
      }
      {
        config.schema.host = {
          priority = 50;
        };
      }
    ];
  };
in
{
  flake.tests.collection-explicit.test-last-wins = {
    expr = eval.config.schema.host.priority;
    expected = 50;
  };
}
