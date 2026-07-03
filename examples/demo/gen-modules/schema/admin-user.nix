# Admin user kind: mixes in the base user kind and adds admin-specific fields.
#
# Demonstrates kind-level composition via imports — admin-user inherits all
# of user's options (userName, shell) and adds its own (sudoPrivileges, sshKeys).
# Both kinds get their own registries with independent instances.
{ lib, config, ... }:
{
  config.schema.admin-user = {
    imports = [ config.schema.user ];
    options.sudoPrivileges = lib.mkOption {
      type = lib.types.bool;
      description = "Whether this admin has sudo access.";
      default = true;
    };
    options.sshKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "Authorized SSH public keys.";
      default = [ ];
    };
  };
}
