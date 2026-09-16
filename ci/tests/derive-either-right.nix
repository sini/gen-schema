{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  schema = genSchema.evalSchema {
    modules = [
      {
        config.schema.host = {
          options.addr = genMerge.mkOption { type = genMerge.types.str; };
        };
      }
    ];
  };

  eval = genMerge.evalModuleTree {
    modules = [
      {
        options.hosts = genSchema.mkInstanceRegistry schema.host {
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
