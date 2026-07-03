{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) mkSchemaOption;

  eval = genMerge.evalModuleTree {
    modules = [
      {
        options.schema = mkSchemaOption {
          collections.includes = {
            default = [ ];
          };
        };
        config.schema.host = {
          options.name = genMerge.mkOption { type = genMerge.types.str; };
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
  flake.tests.collection-list.test-merged-includes = {
    expr = eval.config.schema.host.includes;
    expected = [
      "networking"
      "monitoring"
    ];
  };
}
