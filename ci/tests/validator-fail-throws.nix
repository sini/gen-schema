{
  lib,
  genSchema,
  genMerge,
  genAlgebra,
  ...
}:
let
  schemaEval = genMerge.evalModuleTree {
    modules = [
      {
        options.schema = genSchema.mkSchemaOption { };
        config.schema.host = {
          options.addr = genMerge.mkOption { type = genMerge.types.str; };
          validators = [
            (genSchema.mkValidator "has-addr" ({ addr, ... }: addr != "") "addr must not be empty")
          ];
        };
      }
    ];
  };
  hostType = genSchema.mkInstanceType schemaEval.config.schema.host { };
  instanceEval = genMerge.evalModuleTree {
    modules = [
      {
        options.hosts = genMerge.mkOption {
          type = genMerge.types.attrsOf hostType;
          default = { };
        };
        config.hosts.bad = {
          addr = "";
        };
      }
    ];
  };
  result = genSchema.validateInstances schemaEval.config.schema.host instanceEval.config.hosts;
in
{
  flake.tests."validator-fail".test-left-returned = {
    expr = result ? left;
    expected = true;
  };
  flake.tests."validator-fail".test-error-has-instance-name = {
    expr = (lib.head result.left).name;
    expected = "bad";
  };
  flake.tests."validator-fail".test-error-has-validator-name = {
    expr = (lib.head result.left).validator;
    expected = "has-addr";
  };
}
