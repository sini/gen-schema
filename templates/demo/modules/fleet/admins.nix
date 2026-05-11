# Admin user instances.
#
# Admins inherit all user options (userName, shell) from the base user kind
# via schema import, and add admin-specific fields (sudoPrivileges, sshKeys).
{ ... }:
{
  fleet.admins.root = {
    userName = "root";
    shell = "/bin/bash";
    sshKeys = [
      "ssh-ed25519 AAAAC3Nza..."
    ];
  };

  fleet.admins.deploy = {
    userName = "deploy";
    shell = "/bin/sh";
    sudoPrivileges = false;
    sshKeys = [
      "ssh-ed25519 AAAAC3Nzb..."
      "ssh-ed25519 AAAAC3Nzc..."
    ];
  };
}
