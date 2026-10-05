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
              default = "none";
              internal = true;
            };
          }
        ];
        derive = _instances: {
          igloo = {
            tag = "tagged";
          };
        };
      } schema.host;
      config.hosts.igloo.addr = "10.0.1.1";
      config.hosts.iceberg.addr = "10.0.1.2";
    }
  ];
in
{
  flake.tests."derive-partial" = {
    test-igloo-gets-tag = {
      expr = eval.config.hosts.igloo.tag;
      expected = "tagged";
    };
    test-iceberg-gets-default = {
      expr = eval.config.hosts.iceberg.tag;
      expected = "none";
    };
  };
}
