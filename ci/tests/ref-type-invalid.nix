{
  lib,
  schemaLib,
  genLib,
  ...
}:
let
  inherit (schemaLib) mkSchemaOption mkInstanceRegistry;
  inherit (genLib) mkRefType;

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
                  type = mkRefType eval.config.hosts;
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
        config.services.badref = {
          host = "nonexistent";
          port = 99;
        };
      }
    ];
  };
in
{
  flake.tests.ref-invalid = {
    test-bad-ref-throws = {
      expr = !(builtins.tryEval (builtins.deepSeq eval.config.services.badref.host.addr "ok")).success;
      expected = true;
    };
  };
}
