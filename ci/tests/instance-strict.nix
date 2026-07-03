{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) mkSchemaOption mkInstanceRegistry;

  eval = genMerge.evalModuleTree {
    modules = [
      {
        options.schema = mkSchemaOption { strict = true; };
        options.hosts = mkInstanceRegistry eval.config.schema.host { };
        config.schema.host = {
          options.addr = genMerge.mkOption { type = genMerge.types.str; };
        };
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
