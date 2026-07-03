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
        options.schema = genSchema.mkSchemaOption { };
        options.hosts = genSchema.mkInstanceRegistry eval.config.schema.host {
          extraModules = [
            {
              options.tag = genMerge.mkOption {
                type = genMerge.types.str;
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
          options.addr = genMerge.mkOption { type = genMerge.types.str; };
        };
        config.hosts.igloo.addr = "10.0.1.1";
      }
    ];
  };
in
{
  flake.tests."derive-either-right" = {
    test-tag-applied = {
      expr = eval.config.hosts.igloo.tag;
      expected = "either-igloo";
    };
  };
}
