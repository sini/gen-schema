# Computed fields override collections of the same name.
{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  eval = genMerge.evalModuleTree {
    modules = [
      {
        options.schema = genSchema.mkSchemaOption {
          collections.isEntity = {
            default = false;
            merge = _: v: v;
          };
          computed = _collections: _defs: {
            # Computed isEntity overrides the collection isEntity
            isEntity = true;
          };
        };
        config.schema.host = {
          isEntity = false;
          options.name = genMerge.mkOption { type = genMerge.types.str; };
        };
      }
    ];
  };
in
{
  flake.tests."collection-precedence".test-computed-overrides-collection = {
    expr = eval.config.schema.host.isEntity;
    expected = true;
  };
}
