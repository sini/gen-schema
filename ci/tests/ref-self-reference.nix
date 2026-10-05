{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) evalSchema mkInstanceRegistry declarationOf;

  schema = evalSchema { } [
    {
      config.schema.service = {
        options.port = genMerge.mkOption { type = genMerge.types.int; };
      };
    }
  ];

  eval = genMerge.evalModuleTree { } [
    {
      options.services = mkInstanceRegistry {
        extraModules = [
          (
            { ... }:
            {
              options.upstream = genMerge.mkOption {
                type = genMerge.types.nullOr (declarationOf eval.config.services);
                default = null;
              };
            }
          )
        ];
      } schema.service;
      config.services.api = {
        port = 8080;
      };
      config.services.gateway = {
        port = 443;
        upstream = "api";
      };
    }
  ];
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
