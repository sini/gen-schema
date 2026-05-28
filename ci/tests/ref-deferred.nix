{
  lib,
  schemaLib,
  ...
}:
let
  inherit (schemaLib) mkSchemaOption mkInstanceRegistry ref;

  eval = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption { };
        options.hosts = mkInstanceRegistry eval.config.schema.host { };
        options.services = mkInstanceRegistry eval.config.schema.service {
          refs.host = eval.config.hosts;
        };
        config.schema.host = {
          options.addr = lib.mkOption { type = lib.types.str; };
          options.role = lib.mkOption { type = lib.types.str; };
        };
        config.schema.service = {
          options.port = lib.mkOption { type = lib.types.int; };
          options.host = lib.mkOption { type = ref "host"; };
        };
        config.hosts.igloo = {
          addr = "10.0.1.1";
          role = "web";
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
  flake.tests.ref-deferred = {
    test-deferred-ref-resolves-addr = {
      expr = nginx.host.addr;
      expected = "10.0.1.1";
    };
    test-deferred-ref-resolves-name = {
      expr = nginx.host.name;
      expected = "igloo";
    };
    test-deferred-ref-has-id-hash = {
      expr = builtins.isString nginx.host.id_hash;
      expected = true;
    };
  };
}
