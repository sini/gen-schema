{ lib, schemaLib, ... }:
let
  eval = lib.evalModules {
    modules = [
      {
        options.schema = schemaLib.mkSchemaOption { };
        options.hosts = schemaLib.mkInstanceRegistry eval.config.schema "host" {
          extraModules = [
            {
              options.tag = lib.mkOption {
                type = lib.types.str;
                default = "fallback";
                internal = true;
              };
            }
          ];
          deriveEither = {
            derive = _instances: { left = "error"; };
            onError = _: { };
          };
        };
        config.schema.host = {
          options.addr = lib.mkOption { type = lib.types.str; };
        };
        config.hosts.igloo.addr = "10.0.1.1";
      }
    ];
  };
in
{
  flake.tests."derive-either-custom" = {
    test-no-throw = {
      expr =
        (builtins.tryEval (builtins.deepSeq eval.config.hosts.igloo.addr eval.config.hosts.igloo.addr))
        .success;
      expected = true;
    };
    test-fallback-tag = {
      expr = eval.config.hosts.igloo.tag;
      expected = "fallback";
    };
  };
}
