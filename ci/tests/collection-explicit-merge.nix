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
          collections.priority = {
            default = 0;
            merge = _acc: val: val;
          };
        };
        config.schema.host = {
          options.name = genMerge.mkOption { type = genMerge.types.str; };
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
