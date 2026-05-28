# validateInstances is a standalone function that returns Either without throwing.
# It operates independently of the registry pipeline.
{
  lib,
  schemaLib,
  genLib,
  ...
}:
let
  # Build schema with validators, but create instances manually (not via registry)
  # to avoid the registry's apply pipeline throwing on validation failure.
  schemaEval = lib.evalModules {
    modules = [
      {
        options.schema = schemaLib.mkSchemaOption { };
        config.schema.host = {
          options.addr = lib.mkOption { type = lib.types.str; };
          validators = [
            (genLib.mkValidator "has-addr" ({ addr, ... }: addr != "") "need addr")
          ];
        };
      }
    ];
  };

  # Create instances directly via mkInstanceType (no apply pipeline)
  hostType = schemaLib.mkInstanceType schemaEval.config.schema.host { };
  instanceEval = lib.evalModules {
    modules = [
      {
        options.hosts = lib.mkOption {
          type = lib.types.attrsOf hostType;
          default = { };
        };
        config.hosts.good.addr = "10.0.1.1";
        config.hosts.bad.addr = "";
      }
    ];
  };

  result = schemaLib.validateInstances schemaEval.config.schema "host" instanceEval.config.hosts;
in
{
  flake.tests."validate-standalone".test-returns-either = {
    expr = result ? left || result ? right;
    expected = true;
  };
  flake.tests."validate-standalone".test-has-errors = {
    expr = result ? left;
    expected = true;
  };
  flake.tests."validate-standalone".test-does-not-throw = {
    expr = (builtins.tryEval result).success;
    expected = true;
  };
}
