{ lib, schemaLib, ... }:
let
  inherit (schemaLib) mkSchemaOption;

  eval = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption {
          collections.includes = {
            default = [ ];
          };
          collections.excludes = {
            default = [ ];
          };
          computed =
            collections: defs:
            let
              hasStructural = lib.any (
                d: builtins.isAttrs d.value && (d.value ? options || d.value ? config)
              ) defs;
              hasCollections = collections.includes != [ ] || collections.excludes != [ ];
            in
            {
              isEntity = hasStructural || hasCollections;
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
  flake.tests.entity-detect.test-host-is-entity = {
    expr = eval.config.schema.host.isEntity;
    expected = true;
  };
  flake.tests.entity-detect.test-tag-not-entity = {
    expr = eval.config.schema.tag.isEntity;
    expected = false;
  };
  flake.tests.entity-detect.test-app-is-entity = {
    expr = eval.config.schema.app.isEntity;
    expected = true;
  };
}
