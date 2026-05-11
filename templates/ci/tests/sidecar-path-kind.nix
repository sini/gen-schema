# Path-based kind declarations skip sidecar extraction (isAttrs check).
# Sidecars on path defs are not extracted — the kind should still work,
# getting the sidecar default value.
{ lib, schemaLib, ... }:
let
  eval = lib.evalModules {
    modules = [{
      options.schema = schemaLib.mkSchemaOption {
        sidecars.includes = { default = []; };
      };
      # host defined via path — sidecar extraction is skipped
      config.schema.host = ../test-fixtures/sidecar-path-kind-host.nix;
    }];
  };
in
{
  "sidecar-path".test-path-kind-gets-default = {
    expr = eval.config.schema.host.includes;
    expected = [];
  };
  "sidecar-path".test-path-kind-still-callable = {
    expr = builtins.isFunction (eval.config.schema.host.__functor eval.config.schema.host);
    expected = true;
  };
}
