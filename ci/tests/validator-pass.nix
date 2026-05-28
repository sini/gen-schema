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
          options.role = lib.mkOption { type = lib.types.str; };
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
        config.hosts.igloo = {
          addr = "10.0.1.1";
          role = "web";
        };
      }
    ];
  };
  result = schemaLib.validateInstances schemaEval.config.schema "host" instanceEval.config.hosts;
in
{
  flake.tests."validator-pass".test-right-returned = {
    expr = result ? right;
    expected = true;
  };
}
