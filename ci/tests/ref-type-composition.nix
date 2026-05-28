{
  lib,
  schemaLib,
  genLib,
  ...
}:
let
  inherit (schemaLib) mkSchemaOption mkInstanceRegistry;
  inherit (genLib) mkRefType;

  # Two separate modules: one defines hosts, another defines services with refs
  eval = lib.evalModules {
    modules = [
      # Module 1: schema + hosts
      {
        options.schema = mkSchemaOption { };
        options.hosts = mkInstanceRegistry eval.config.schema.host { };
        config.schema.host = {
          options.addr = lib.mkOption { type = lib.types.str; };
        };
        config.schema.service = {
          options.port = lib.mkOption { type = lib.types.int; };
        };
        config.hosts.igloo = {
          addr = "10.0.1.1";
        };
      }
      # Module 2: services with ref to hosts
      {
        options.services = mkInstanceRegistry eval.config.schema.service {
          extraModules = [
            (
              { ... }:
              {
                options.host = lib.mkOption {
                  type = mkRefType eval.config.hosts;
                };
              }
            )
          ];
        };
        config.services.nginx = {
          host = "igloo";
          port = 80;
        };
      }
    ];
  };
in
{
  flake.tests.ref-compose = {
    test-cross-module-ref-resolves = {
      expr = eval.config.services.nginx.host.addr;
      expected = "10.0.1.1";
    };
    test-cross-module-ref-name = {
      expr = eval.config.services.nginx.host.name;
      expected = "igloo";
    };
  };
}
