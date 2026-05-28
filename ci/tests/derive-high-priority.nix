{ lib, schemaLib, ... }:
let
  eval = lib.evalModules {
    modules = [
      {
        options.schema = schemaLib.mkSchemaOption { };
        options.hosts = schemaLib.mkInstanceRegistry eval.config.schema.host {
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
