{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  schema = genSchema.evalSchema { } [
    {
      config.schema.host = {
        options.addr = genMerge.mkOption { type = genMerge.types.str; };
      };
    }
  ];

  eval = genMerge.evalModuleTree { } [
    {
      options.hosts = genSchema.mkInstanceRegistry {
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
      } schema.host;
      config.hosts.igloo.addr = "10.0.1.1";
    }
  ];
in
{
  flake.tests."derive-either-right" = {
    test-tag-applied = {
      expr = eval.config.hosts.igloo.tag;
      expected = "either-igloo";
    };
  };
}
