# Row-polymorphic validators (§ Leijen 2005 S3.1).
# Validators with `fields` auto-skip for kinds missing those fields.
# This validator fires only on kinds that have both "port" and "protocol".
{ genSchema, ... }:
{
  config.schema.service.validators = [
    (genSchema.mkFieldValidator {
      name = "https-port";
      fields = [
        "port"
        "protocol"
      ];
      check = inst: !(inst.protocol == "https" && inst.port == 80);
      message = "HTTPS should not use port 80";
    })
  ];
}
