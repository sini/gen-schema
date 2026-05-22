# Computed fields override sidecars of the same name.
{ lib, schemaLib, ... }:
let
  eval = lib.evalModules {
<<<<<<< Updated upstream
    modules = [
      {
        options.schema = schemaLib.mkSchemaOption {
          sidecars.isEntity = {
            default = false;
            merge = _: v: v;
          };
          computed = _kind: sidecars: _defs: {
            # Computed isEntity overrides the sidecar isEntity
            isEntity = true;
          };
||||||| Stash base
    modules = [{
      options.schema = schemaLib.mkSchemaOption {
        sidecars.isEntity = { default = false; merge = _: v: v; };
        computed = _kind: sidecars: _defs: {
          # Computed isEntity overrides the sidecar isEntity
          isEntity = true;
=======
    modules = [
      {
        options.schema = schemaLib.mkSchemaOption {
          sidecars.isEntity = {
            default = false;
            merge = _: v: v;
          };
          computed = _sidecars: _defs: {
            # Computed isEntity overrides the sidecar isEntity
            isEntity = true;
          };
>>>>>>> Stashed changes
        };
        config.schema.host = {
          isEntity = false;
          options.name = lib.mkOption { type = lib.types.str; };
        };
      }
    ];
  };
in
{
  "sidecar-precedence".test-computed-overrides-sidecar = {
    expr = eval.config.schema.host.isEntity;
    expected = true;
  };
}
