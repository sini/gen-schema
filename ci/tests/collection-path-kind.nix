# Path-based kind declarations skip collection extraction (isAttrs check).
# Collections on path defs are not extracted — the kind should still work,
# getting the collection default value.
{ lib, schemaLib, ... }:
let
  eval = lib.evalModules {
    modules = [
      {
        options.schema = schemaLib.mkSchemaOption {
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
  "collection-path".test-path-kind-gets-default = {
    expr = eval.config.schema.host.includes;
    expected = [ ];
  };
  "collection-path".test-path-kind-still-callable = {
    expr = builtins.isFunction (eval.config.schema.host.__functor eval.config.schema.host);
    expected = true;
  };
}
