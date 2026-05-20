{ lib, schemaLib, genLib, ... }:
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
  hostType = schemaLib.mkInstanceType schemaEval.config.schema "host" { };
  instanceEval = lib.evalModules {
    modules = [
      {
        options.hosts = lib.mkOption {
          type = lib.types.attrsOf hostType;
          default = { };
        };
        config.hosts.bad = {
          addr = "";
        };
      }
    ];
  };
  result = schemaLib.validateInstances schemaEval.config.schema "host" instanceEval.config.hosts;
in
{
  "validator-fail".test-left-returned = {
    expr = result ? left;
    expected = true;
  };
  "validator-fail".test-error-has-instance-name = {
    expr = (lib.head result.left).name;
    expected = "bad";
  };
  "validator-fail".test-error-has-validator-name = {
    expr = (lib.head result.left).validator;
    expected = "has-addr";
  };
}
