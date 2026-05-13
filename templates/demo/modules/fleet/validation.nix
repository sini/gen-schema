# Schema-level validators — travel with the kind, run automatically.
{ lib, schemaLib, ... }:
{
  config.schema.host.validators = [
    (schemaLib.mkValidator "has-addr" ({ addr, ... }: addr != "") "host must have a non-empty addr")
    (schemaLib.mkValidator "valid-role" (
      { role, ... }:
      lib.elem role [
        "web"
        "db"
        "worker"
        "lb"
      ]
    ) "role must be one of: web, db, worker, lb")
  ];
}
