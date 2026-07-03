{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  schemaEval = genMerge.evalModuleTree {
    modules = [
      {
        options.schema = genSchema.mkSchemaOption { };
        config.schema.host = {
          options.addr = genMerge.mkOption { type = genMerge.types.str; };
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
