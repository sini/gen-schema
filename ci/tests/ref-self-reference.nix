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
        options.services = mkInstanceRegistry eval.config.schema.service {
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
        };
        config.schema.service = {
          options.port = genMerge.mkOption { type = genMerge.types.int; };
        };
        config.services.api = {
          port = 8080;
        };
        config.services.gateway = {
          port = 443;
          upstream = "api";
        };
      }
    ];
  };
in
{
  flake.tests.ref-self-reference = {
    test-self-ref-resolves = {
      expr = eval.config.services.gateway.upstream.port;
      expected = 8080;
    };
    test-self-ref-null-default = {
      expr = eval.config.services.api.upstream;
      expected = null;
    };
  };
}
