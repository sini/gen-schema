{
  lib,
  genSchema,
  genAlgebra,
  ...
}:
let
  inherit (genSchema) mkSchemaOption mkInstanceRegistry;
  inherit (genAlgebra) mkRefType;

  eval = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption { };
        options.hosts = mkInstanceRegistry eval.config.schema.host { };
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
        config.schema.host = {
          options.addr = lib.mkOption { type = lib.types.str; };
          options.role = lib.mkOption { type = lib.types.str; };
        };
        config.schema.service = {
          options.port = lib.mkOption { type = lib.types.int; };
        };
        config.hosts.igloo = {
          addr = "10.0.1.1";
          role = "web";
        };
        config.hosts.yurt = {
          addr = "10.0.1.2";
          role = "db";
        };
        config.services.nginx = {
          host = "igloo";
          port = 80;
        };
      }
    ];
  };

  inherit (eval.config.services) nginx;
in
{
  flake.tests.ref-valid = {
    test-ref-resolves-to-addr = {
      expr = nginx.host.addr;
      expected = "10.0.1.1";
    };
    test-ref-resolves-to-role = {
      expr = nginx.host.role;
      expected = "web";
    };
    test-ref-resolves-to-name = {
      expr = nginx.host.name;
      expected = "igloo";
    };
    test-ref-has-id-hash = {
      expr = builtins.isString nginx.host.id_hash;
      expected = true;
    };
  };
}
