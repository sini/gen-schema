{
  lib,
  schemaLib,
  genLib,
  ...
}:
let
  inherit (schemaLib) mkSchemaOption mkInstanceRegistry ref;

  eval = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption { };
        options.hosts = mkInstanceRegistry eval.config.schema "host" { };
        options.services = mkInstanceRegistry eval.config.schema "service" {
          extraModules = [
            (
              { ... }:
              {
                options.host = lib.mkOption {
                  type = ref eval.config.hosts;
                };
              }
            )
          ];
        };
        config.schema.host = {
          options.addr = lib.mkOption { type = lib.types.str; };
        };
        config.schema.service = {
          options.port = lib.mkOption { type = lib.types.int; };
        };
        config.hosts.igloo = {
          addr = "10.0.1.1";
        };
        config.services.nginx = {
          host = "igloo";
          port = 80;
        };
      }
    ];
  };

  nginx = eval.config.services.nginx;
in
{
  ref-direct = {
    test-direct-ref-resolves-addr = {
      expr = nginx.host.addr;
      expected = "10.0.1.1";
    };
    test-direct-ref-resolves-name = {
      expr = nginx.host.name;
      expected = "igloo";
    };
  };
}
