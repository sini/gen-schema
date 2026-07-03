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
