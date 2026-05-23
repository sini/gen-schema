# Group kind: named sets of hosts.
# Demonstrates setOf — deduplication by identity hash.
{ lib, schemaLib, ... }:
{
  config.schema.group = {
    options.members = lib.mkOption {
      type = schemaLib.setOf (schemaLib.ref "host");
      default = [ ];
      description = "Unique set of hosts in this group.";
    };
  };
}
