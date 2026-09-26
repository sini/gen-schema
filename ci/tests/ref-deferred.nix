{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) evalSchema mkInstanceRegistry declarationOf;

  schema = evalSchema {
    modules = [
      {
        config.schema.host = {
          options.addr = genMerge.mkOption { type = genMerge.types.str; };
          options.role = genMerge.mkOption { type = genMerge.types.str; };
        };
        config.schema.service = {
          options.port = genMerge.mkOption { type = genMerge.types.int; };
          options.host = genMerge.mkOption { type = declarationOf "host"; };
        };
      }
    ];
  };

  eval = genMerge.evalModuleTree {
    modules = [
      {
        options.hosts = mkInstanceRegistry schema.host { };
        options.services = mkInstanceRegistry schema.service {
          refs.host = eval.config.hosts;
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
