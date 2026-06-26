{
  lib,
  genSchema,
  genAlgebra,
  ...
}:
let
  schemaEval = lib.evalModules {
    modules = [
      {
        options.schema = genSchema.mkSchemaOption { };
        config.schema.host = {
          options.addr = lib.mkOption { type = lib.types.str; };
          options.role = lib.mkOption { type = lib.types.str; };
          validators = [
            (genSchema.mkValidator "has-addr" ({ addr, ... }: addr != "") "addr must not be empty")
            (genSchema.mkValidator "valid-role" (
              { role, ... }:
              lib.elem role [
                "web"
                "db"
                "worker"
              ]
            ) "role must be web, db, or worker")
          ];
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
        config.hosts.bad = {
          addr = "";
          role = "invalid";
        };
        config.hosts.good = {
          addr = "10.0.1.1";
          role = "web";
        };
      }
    ];
  };
  result = genSchema.validateInstances schemaEval.config.schema.host instanceEval.config.hosts;
in
{
  flake.tests."validator-multi".test-accumulates-errors = {
    expr = lib.length result.left;
    expected = 2;
  };
  flake.tests."validator-multi".test-only-bad-instance = {
    expr = lib.all (f: f.name == "bad") result.left;
    expected = true;
  };
}
