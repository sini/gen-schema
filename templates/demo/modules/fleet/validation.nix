# Schema-level validators — travel with the kind, run automatically.
# Validators declared here fire on every registry of that kind.
{ lib, schemaLib, ... }:
{
  config.schema.host.validators = [
    (schemaLib.mkValidator "has-addr"
      ({ addr, ... }: addr != "")
      "host must have a non-empty addr")
    (schemaLib.mkValidator "valid-role"
      ({ role, ... }: lib.elem role [ "web" "db" "worker" "lb" ])
      "role must be one of: web, db, worker, lb")
  ];

  # Port validation belongs on the kind, not in a derive hook
  config.schema.service.validators = [
    (schemaLib.mkValidator "valid-port"
      ({ port, ... }: port > 0 && port < 65536)
      "port must be between 1 and 65535")
  ];
}
