{ lib, genSchema, ... }:
let
  eval = lib.evalModules {
    modules = [
      {
        options.schema = genSchema.mkSchemaOption { };
        options.hosts = genSchema.mkInstanceRegistry eval.config.schema.host {
          extraModules = [
            {
              options.tag = lib.mkOption {
                type = lib.types.str;
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
        };
        config.schema.host = {
          options.addr = lib.mkOption { type = lib.types.str; };
        };
        config.hosts.igloo.addr = "10.0.1.1";
        config.hosts.iceberg.addr = "10.0.1.2";
      }
    ];
  };
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
