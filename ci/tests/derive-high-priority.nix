{ lib, genSchema, ... }:
let
  eval = lib.evalModules {
    modules = [
      {
        options.schema = genSchema.mkSchemaOption { };
        options.hosts = genSchema.mkInstanceRegistry eval.config.schema.host {
          extraModules = [
            {
              options.computed = lib.mkOption {
                type = lib.types.str;
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
          options.addr = lib.mkOption { type = lib.types.str; };
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
