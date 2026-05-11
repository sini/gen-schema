{ lib, schemaLib, ... }:
let
  inherit (schemaLib) mkSchemaOption;

  eval = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption {
          sidecars.metadata = {
            default = { };
          };
        };
        config.schema.host = {
          options.name = lib.mkOption { type = lib.types.str; };
          metadata.tier = "production";
        };
      }
      {
        config.schema.host = {
          metadata.region = "us-east";
        };
      }
    ];
  };
in
{
  sidecar-attrs.test-merged-metadata = {
    expr = eval.config.schema.host.metadata;
    expected = {
      tier = "production";
      region = "us-east";
    };
  };
}
