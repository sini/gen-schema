# Group kind: named sets of hosts.
# Demonstrates setOf — deduplication by identity hash.
{ lib, genSchema, ... }:
{
  config.schema.group = {
    options.members = lib.mkOption {
      type = genSchema.setOf (genSchema.ref "host");
      default = [ ];
      description = "Unique set of hosts in this group.";
    };
  };
}
