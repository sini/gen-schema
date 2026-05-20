{ lib, schemaLib, genLib, ... }:
let
  inherit (schemaLib) mkSchemaOption mkInstanceRegistry ref;

  eval = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption { };
        options.services = mkInstanceRegistry eval.config.schema "service" {
          extraModules = [
            ({ ... }: {
              options.upstream = lib.mkOption {
                type = lib.types.nullOr (ref eval.config.services);
                default = null;
              };
            })
          ];
        };
        config.schema.service = {
          options.port = lib.mkOption { type = lib.types.int; };
        };
        config.services.api = { port = 8080; };
        config.services.gateway = {
          port = 443;
          upstream = "api";
        };
      }
    ];
  };
in
{
  ref-self-reference = {
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
