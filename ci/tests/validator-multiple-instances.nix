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
        config.hosts.good-a = {
          addr = "10.0.1.1";
        };
        config.hosts.good-b = {
          addr = "10.0.1.2";
        };
        config.hosts.bad-a = {
          addr = "";
        };
        config.hosts.bad-b = {
          addr = "";
        };
      }
    ];
  };
  result = genSchema.validateInstances schemaEval.config.schema.host instanceEval.config.hosts;
  failedNames = lib.sort (a: b: a < b) (map (f: f.name) result.left);
in
{
  flake.tests."validator-instances".test-left-returned = {
    expr = result ? left;
    expected = true;
  };
  flake.tests."validator-instances".test-only-failing-instances = {
    expr = failedNames;
    expected = [
      "bad-a"
      "bad-b"
    ];
  };
  flake.tests."validator-instances".test-error-count = {
    expr = lib.length result.left;
    expected = 2;
  };
}
