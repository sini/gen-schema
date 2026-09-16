{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) evalSchema mkInstanceRegistry ref;

  schema = evalSchema {
    modules = [
      {
        config.schema.host = {
          options.addr = genMerge.mkOption { type = genMerge.types.str; };
        };
        config.schema.service = {
          options.port = genMerge.mkOption { type = genMerge.types.int; };
          options.host = genMerge.mkOption { type = ref "host"; };
        };
      }
    ];
  };

  eval = genMerge.evalModuleTree {
    modules = [
      {
        options.hosts = mkInstanceRegistry schema.host { };
        options.services = mkInstanceRegistry schema.service {
          extraModules = [
            (
              { ... }:
              {
                options.upstream = genMerge.mkOption {
                  type = genMerge.types.nullOr (ref eval.config.services);
                  default = null;
                };
              }
            )
          ];
          refs.host = eval.config.hosts;
        };
        config.hosts.igloo = {
          addr = "10.0.1.1";
        };
        config.services.api = {
          host = "igloo";
          port = 8080;
        };
        config.services.gateway = {
          host = "igloo";
          port = 443;
          upstream = "api";
        };
        config.services.standalone = {
          host = "igloo";
          port = 9090;
          # upstream defaults to null
        };
      }
    ];
  };
in
{
  flake.tests.ref-nullable = {
    test-nullable-ref-resolves = {
      expr = eval.config.services.gateway.upstream.port;
      expected = 8080;
    };
    test-nullable-ref-null-default = {
      expr = eval.config.services.standalone.upstream;
      expected = null;
    };
  };
}
