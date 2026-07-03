# Path-based kind declarations skip collection extraction (isAttrs check).
# Collections on path defs are not extracted — the kind should still work,
# getting the collection default value.
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
          collections.includes = {
            default = [ ];
          };
        };
        # host defined via path — collection extraction is skipped
        config.schema.host = ../test-fixtures/collection-path-kind-host.nix;
      }
    ];
  };
in
{
  flake.tests."collection-path".test-path-kind-gets-default = {
    expr = eval.config.schema.host.includes;
    expected = [ ];
  };
  flake.tests."collection-path".test-path-kind-still-callable = {
    expr = builtins.isFunction (eval.config.schema.host.__functor eval.config.schema.host);
    expected = true;
  };
}
