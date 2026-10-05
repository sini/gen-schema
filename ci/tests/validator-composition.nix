{
  lib,
  genSchema,
  genMerge,
  genAlgebra,
  ...
}:
let
  eval = genMerge.evalModuleTree { } [
    { options.schema = genSchema.mkSchemaOption { }; }
    # Module A adds a validator
    {
      config.schema.host.options.addr = genMerge.mkOption { type = genMerge.types.str; };
      config.schema.host.validators = [
        (genSchema.mkValidator {
          name = "has-addr";
          pred = { addr, ... }: addr != "";
          message = "need addr";
        })
      ];
    }
    # Module B adds another validator
    {
      config.schema.host.options.role = genMerge.mkOption { type = genMerge.types.str; };
      config.schema.host.validators = [
        (genSchema.mkValidator {
          name = "valid-role";
          pred =
            { role, ... }:
            lib.elem role [
              "web"
              "db"
            ];
          message = "bad role";
        })
      ];
    }
  ];
in
{
  flake.tests."validator-compose".test-validators-merged = {
    expr = lib.length eval.config.schema.host.validators;
    expected = 2;
  };
}
