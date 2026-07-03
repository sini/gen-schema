{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) mkSchemaOption mkInstanceRegistry ref;

  eval = genMerge.evalModuleTree {
    modules = [
      {
        options.schema = mkSchemaOption { };
        options.hosts = mkInstanceRegistry eval.config.schema.host { };
        options.services = mkInstanceRegistry eval.config.schema.service {
          refs.host = eval.config.hosts;
        };
        config.schema.host = {
          options.addr = genMerge.mkOption { type = genMerge.types.str; };
          options.role = genMerge.mkOption { type = genMerge.types.str; };
        };
        config.schema.service = {
          options.port = genMerge.mkOption { type = genMerge.types.int; };
          options.host = genMerge.mkOption { type = ref "host"; };
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
