# Strict toggle: strict = false on mkSchemaOption flows to instances via mkInstanceRegistry.
{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) evalSchema mkSchemaOption mkInstanceRegistry;

  schema = evalSchema {
    schemaOption = mkSchemaOption { strict = false; };
    modules = [
      { config.schema.host.options.name = genMerge.mkOption { type = genMerge.types.str; }; }
    ];
  };

  eval = genMerge.evalModuleTree {
    modules = [
      {
        options.hosts = mkInstanceRegistry schema.host { };
        config.hosts.igloo = {
          name = "igloo";
          undeclaredKey = "should work";
        };
      }
    ];
  };

  result = builtins.tryEval (builtins.deepSeq eval.config.hosts.igloo eval.config.hosts.igloo);
in
{
  flake.tests.strict-toggle.test-non-strict-accepts-undeclared = {
    expr = result.success;
    expected = true;
  };
  flake.tests.strict-toggle.test-non-strict-declared-key-works = {
    expr = result.value.name;
    expected = "igloo";
  };
}
