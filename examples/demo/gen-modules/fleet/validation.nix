# Schema-level validators — travel with the kind, run automatically.
# Validators declared here fire on every registry of that kind.
{ lib, genSchema, ... }:
let
  inherit (genSchema) mkValidator;
in
{
  config.schema.host.validators = [
    (mkValidator {
      name = "has-addr";
      pred = { addr, ... }: addr != "";
      message = "host must have a non-empty addr";
    })
    (mkValidator {
      name = "valid-role";
      pred =
        { role, ... }:
        lib.elem role [
          "web"
          "db"
          "worker"
          "lb"
        ];
      message = "role must be one of: web, db, worker, lb";
    })
  ];

  # Port validation belongs on the kind, not in a derive hook
  config.schema.service.validators = [
    (mkValidator {
      name = "valid-port";
      pred = { port, ... }: port > 0 && port < 65536;
      message = "port must be between 1 and 65535";
    })
  ];
}
