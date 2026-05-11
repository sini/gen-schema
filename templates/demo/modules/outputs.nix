# Expose fleet data as flake outputs for demonstration.
{ config, ... }:
let
  fleet = config.fleet;
in
{
  flake.fleet = {
    # Instance registry keys
    hostNames = builtins.attrNames fleet.hosts;
    userNames = builtins.attrNames fleet.users;
    serviceNames = builtins.attrNames fleet.services;

    # Field values from instances
    iglooAddr = fleet.hosts.igloo.addr;
    iglooRole = fleet.hosts.igloo.role;

    # Default propagation
    iglooSystem = fleet.hosts.igloo.system;
    icebergSystem = fleet.hosts.iceberg.system;

    # User fields
    tuxShell = fleet.users.tux.shell;
    yetiShell = fleet.users.yeti.shell;

    # Shared base (description from baseModule — empty default)
    iglooDescription = fleet.hosts.igloo.description or "n/a";

    # Identity hash
    iglooHash = fleet.hosts.igloo.id_hash;

    # Cross-instance references
    nginxHost = fleet.services.nginx.host.name;
    nginxHostAddr = fleet.services.nginx.host.addr;
    postgresHost = fleet.services.postgres.host.name;
  };
}
