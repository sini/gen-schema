{ lib, schemaLib, ... }:
let
  inherit (schemaLib) mkSchemaOption;

  eval = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption {
          collections.metadata = {
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
  flake.tests.collection-attrs.test-merged-metadata = {
    expr = eval.config.schema.host.metadata;
    expected = {
      tier = "production";
      region = "us-east";
    };
  };
}
