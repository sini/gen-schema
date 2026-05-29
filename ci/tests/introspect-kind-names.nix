{ lib, genSchema, ... }:
let
  inherit (genSchema) mkSchemaOption;

  eval = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption { };
        config.schema.host = {
          options.name = lib.mkOption { type = lib.types.str; };
        };
        config.schema.user = {
          options.userName = lib.mkOption { type = lib.types.str; };
        };
      }
    ];
  };
in
{
  flake.tests.introspect-names.test-kind-names = {
    expr = eval.config.schema._kindNames;
    expected = [
      "host"
      "user"
    ];
  };
  flake.tests.introspect-names.test-excludes-underscore-prefixed = {
    expr = builtins.elem "_meta" eval.config.schema._kindNames;
    expected = false;
  };
}
