{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) evalSchema mkSchemaOption mkInstanceRegistry;

  schema = evalSchema {
    schemaOption = mkSchemaOption { strict = true; };
    modules = [
      {
        config.schema.host = {
          options.addr = genMerge.mkOption { type = genMerge.types.str; };
        };
      }
    ];
  };

  eval = genMerge.evalModuleTree {
    modules = [
      {
        options.hosts = mkInstanceRegistry schema.host { };
        config.hosts.igloo = {
          addr = "10.0.1.1";
          bogus = "should-fail";
        };
      }
    ];
  };

  result = builtins.tryEval (builtins.deepSeq eval.config.hosts.igloo eval.config.hosts.igloo);
in
{
  flake.tests.instance-strict = {
    test-strict-rejects-undeclared = {
      expr = result.success;
      expected = false;
    };
  };
}
