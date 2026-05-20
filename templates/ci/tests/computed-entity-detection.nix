{ lib, schemaLib, ... }:
let
  inherit (schemaLib) mkSchemaOption;

  eval = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption {
          sidecars.includes = {
            default = [ ];
          };
          sidecars.excludes = {
            default = [ ];
          };
          computed =
            _kind: sidecars: defs:
            let
              hasStructural = lib.any (
                d: builtins.isAttrs d.value && (d.value ? options || d.value ? config)
              ) defs;
              hasSidecars = sidecars.includes != [ ] || sidecars.excludes != [ ];
            in
            {
              isEntity = hasStructural || hasSidecars;
            };
        };
        # Kind with includes (entity)
        config.schema.host = {
          options.name = lib.mkOption { type = lib.types.str; };
          includes = [ "networking" ];
        };
        # Empty kind (not entity)
        config.schema.tag = { };
        # Kind with structural content only (entity)
        config.schema.app = {
          options.version = lib.mkOption { type = lib.types.str; };
        };
      }
    ];
  };
in
{
  entity-detect.test-host-is-entity = {
    expr = eval.config.schema.host.isEntity;
    expected = true;
  };
  entity-detect.test-tag-not-entity = {
    expr = eval.config.schema.tag.isEntity;
    expected = false;
  };
  entity-detect.test-app-is-entity = {
    expr = eval.config.schema.app.isEntity;
    expected = true;
  };
}
