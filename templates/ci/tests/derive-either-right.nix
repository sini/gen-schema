{ lib, schemaLib, ... }:
let
  eval = lib.evalModules {
    modules = [
      {
        options.schema = schemaLib.mkSchemaOption { };
        options.hosts = schemaLib.mkInstanceRegistry eval.config.schema "host" {
          extraModules = [
            {
              options.tag = lib.mkOption {
                type = lib.types.str;
                readOnly = true;
                internal = true;
              };
            }
          ];
          deriveEither = {
            derive = instances: { right = lib.mapAttrs (name: _: { tag = "either-${name}"; }) instances; };
          };
        };
        config.schema.host = {
          options.addr = lib.mkOption { type = lib.types.str; };
        };
        config.hosts.igloo.addr = "10.0.1.1";
      }
    ];
  };
in
{
  "derive-either-right" = {
    test-tag-applied = {
      expr = eval.config.hosts.igloo.tag;
      expected = "either-igloo";
    };
  };
}
