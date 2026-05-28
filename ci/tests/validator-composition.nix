{
  lib,
  schemaLib,
  genLib,
  ...
}:
let
  eval = lib.evalModules {
    modules = [
      { options.schema = schemaLib.mkSchemaOption { }; }
      # Module A adds a validator
      {
        config.schema.host.options.addr = lib.mkOption { type = lib.types.str; };
        config.schema.host.validators = [
          (genLib.mkValidator "has-addr" ({ addr, ... }: addr != "") "need addr")
        ];
      }
      # Module B adds another validator
      {
        config.schema.host.options.role = lib.mkOption { type = lib.types.str; };
        config.schema.host.validators = [
          (genLib.mkValidator "valid-role" (
            { role, ... }:
            lib.elem role [
              "web"
              "db"
            ]
          ) "bad role")
        ];
      }
    ];
  };
in
{
  flake.tests."validator-compose".test-validators-merged = {
    expr = lib.length eval.config.schema.host.validators;
    expected = 2;
  };
}
