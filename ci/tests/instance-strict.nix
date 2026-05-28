{ lib, schemaLib, ... }:
let
  inherit (schemaLib) mkSchemaOption mkInstanceRegistry;

  eval = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption { strict = true; };
        options.hosts = mkInstanceRegistry eval.config.schema.host { };
        config.schema.host = {
          options.addr = lib.mkOption { type = lib.types.str; };
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
