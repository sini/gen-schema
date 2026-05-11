{ lib, schemaLib, ... }:
let
  inherit (schemaLib) mkSchemaOption;

  eval = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption {
          sidecars.includes = {
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
  sidecar-default.test-empty-default = {
    expr = eval.config.schema.host.includes;
    expected = [ ];
  };
}
