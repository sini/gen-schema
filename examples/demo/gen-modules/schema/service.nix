# Service kind: services running on hosts.
# Demonstrates deferred ref: host is declared as ref "host" on the kind,
# bound to a concrete registry via refs on mkInstanceRegistry.
{ lib, genSchema, ... }:
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
      type = genSchema.ref "host";
      description = "Host this service runs on (deferred ref, bound at registry).";
    };
    options.replicas = lib.mkOption {
      type = lib.types.listOf (genSchema.ref "host");
      default = [ ];
      description = "Hosts this service is replicated to.";
    };
    config.protocol = lib.mkDefault "tcp";
  };
}
