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
        };
        config.schema.host = {
          options.addr = genMerge.mkOption { type = genMerge.types.str; };
        };
        config.hosts.igloo = {
          addr = "10.0.1.1";
          computed = "from-instance";
        };
      }
    ];
  };
in
{
  flake.tests."derive-priority" = {
    test-derive-wins = {
      expr = eval.config.hosts.igloo.computed;
      expected = "from-derive";
    };
  };
}
