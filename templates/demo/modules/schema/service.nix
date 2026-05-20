# Service kind: services running on hosts.
# Demonstrates deferred ref: host is declared as ref "host" on the kind,
# bound to a concrete registry via refs on mkInstanceRegistry.
{ lib, schemaLib, ... }:
{
  config.schema.service = {
    options.port = lib.mkOption {
      type = lib.types.int;
      description = "Service port number.";
    };
    options.protocol = lib.mkOption {
      type = lib.types.str;
      description = "Network protocol (tcp, udp, ...).";
    };
    options.host = lib.mkOption {
      type = schemaLib.ref "host";
      description = "Host this service runs on (deferred ref, bound at registry).";
    };
    config.protocol = lib.mkDefault "tcp";
  };
}
