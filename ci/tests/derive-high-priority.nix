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
            options.computed = genMerge.mkOption {
              type = genMerge.types.str;
              internal = true;
            };
          }
        ];
        derive = _instances: {
          igloo = {
            computed = "from-derive";
          };
        };
      } schema.host;
      config.hosts.igloo = {
        addr = "10.0.1.1";
        computed = "from-instance";
      };
    }
  ];
in
{
  flake.tests."derive-priority" = {
    test-derive-wins = {
      expr = eval.config.hosts.igloo.computed;
      expected = "from-derive";
    };
  };
}
