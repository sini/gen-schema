# Strict toggle: strict = false on mkSchemaOption flows to instances via mkInstanceRegistry.
{ lib, genSchema, ... }:
let
  inherit (genSchema) mkSchemaOption mkInstanceRegistry;

  eval = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption { strict = false; };
        options.hosts = mkInstanceRegistry eval.config.schema.host { };
        config.schema.host.options.name = lib.mkOption { type = lib.types.str; };
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
