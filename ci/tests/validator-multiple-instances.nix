{
  lib,
  schemaLib,
  genLib,
  ...
}:
let
  schemaEval = lib.evalModules {
    modules = [
      {
        options.schema = schemaLib.mkSchemaOption { };
        config.schema.host = {
          options.addr = lib.mkOption { type = lib.types.str; };
          validators = [
            (genLib.mkValidator "has-addr" ({ addr, ... }: addr != "") "addr must not be empty")
          ];
        };
      }
    ];
  };
  hostType = schemaLib.mkInstanceType schemaEval.config.schema.host { };
  instanceEval = lib.evalModules {
    modules = [
      {
        options.hosts = lib.mkOption {
          type = lib.types.attrsOf hostType;
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
  result = schemaLib.validateInstances schemaEval.config.schema.host instanceEval.config.hosts;
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
