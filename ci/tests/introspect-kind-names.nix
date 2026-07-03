{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) mkSchemaOption;

  eval = genMerge.evalModuleTree {
    modules = [
      {
        options.schema = mkSchemaOption { };
        config.schema.host = {
          options.name = genMerge.mkOption { type = genMerge.types.str; };
        };
        config.schema.user = {
          options.userName = genMerge.mkOption { type = genMerge.types.str; };
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
