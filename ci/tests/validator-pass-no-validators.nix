{ lib, genSchema, ... }:
let
  schemaEval = lib.evalModules {
    modules = [
      {
        options.schema = genSchema.mkSchemaOption { };
        config.schema.host = {
          options.addr = lib.mkOption { type = lib.types.str; };
        };
      }
    ];
  };
  hostType = genSchema.mkInstanceType schemaEval.config.schema.host { };
  instanceEval = lib.evalModules {
    modules = [
      {
        options.hosts = lib.mkOption {
          type = lib.types.attrsOf hostType;
          default = { };
        };
        config.hosts.igloo = {
          addr = "10.0.1.1";
        };
      }
    ];
  };
  result = genSchema.validateInstances schemaEval.config.schema.host instanceEval.config.hosts;
in
{
  flake.tests."validator-none".test-right-when-no-validators = {
    expr = result ? right;
    expected = true;
  };
  flake.tests."validator-none".test-instances-pass-through = {
    expr = result.right.igloo.addr;
    expected = "10.0.1.1";
  };
}
