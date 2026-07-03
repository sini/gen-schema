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
          options.role = genMerge.mkOption { type = genMerge.types.str; };
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
        config.hosts.igloo = {
          addr = "10.0.1.1";
          role = "web";
        };
      }
    ];
  };
  result = genSchema.validateInstances schemaEval.config.schema.host instanceEval.config.hosts;
in
{
  flake.tests."validator-pass".test-right-returned = {
    expr = result ? right;
    expected = true;
  };
}
