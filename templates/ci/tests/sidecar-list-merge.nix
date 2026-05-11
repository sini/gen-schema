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
          includes = [ "networking" ];
        };
      }
      {
        config.schema.host = {
          includes = [ "monitoring" ];
        };
      }
    ];
  };
in
{
  sidecar-list.test-merged-includes = {
    expr = eval.config.schema.host.includes;
    expected = [
      "networking"
      "monitoring"
    ];
  };
}
