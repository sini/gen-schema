{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) mkSchemaOption;

  result = builtins.tryEval (
    let
      eval = genMerge.evalModuleTree {
        modules = [
          {
            options.schema = mkSchemaOption {
              collections.priority = {
                default = 0;
              };
            };
            config.schema.host = {
              options.name = genMerge.mkOption { type = genMerge.types.str; };
              priority = 10;
            };
          }
        ];
      };
    in
    builtins.deepSeq eval.config.schema.host eval.config.schema.host
  );
in
{
  flake.tests.collection-no-merge.test-int-default-throws = {
    expr = result.success;
    expected = false;
  };
}
