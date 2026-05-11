# Expose fleet data as flake outputs for demonstration.
{ config, schemaLib, ... }:
let
  fleet = config.fleet;
in
{
  flake = {
    fleet = {
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

      # Identity hash
      iglooHash = fleet.hosts.igloo.id_hash;

      # Cross-instance references
      nginxHost = fleet.services.nginx.host.name;
      nginxHostAddr = fleet.services.nginx.host.addr;
      postgresHost = fleet.services.postgres.host.name;

      # --- Schema composition ---
      # Fields added by the monitoring plugin, merged into the base host kind
      iglooMetricsPort = fleet.hosts.igloo.metricsPort;
      iglooMonitored = fleet.hosts.igloo.monitored;
      nginxHealthPath = fleet.services.nginx.healthPath;

      # --- Declarative methods ---
      # hasService: closes over fleet.services, receives host name from instance
      iglooHasNginx = fleet.hosts.igloo.hasService "nginx";
      iglooHasPostgres = fleet.hosts.igloo.hasService "postgres";
      icebergHasPostgres = fleet.hosts.iceberg.hasService "postgres";

      # describe: all args resolved from instance config
      iglooDescribe = fleet.hosts.igloo.describe;
      icebergDescribe = fleet.hosts.iceberg.describe;

      # --- Introspection ---
      kindNames = config.schema._meta.kindNames;
      hostOptionCount = builtins.length (config.schema._meta.kindMeta "host").optionNames;
    };

    # --- Documentation generation ---
    docs = schemaLib.renderDocs config.schema;
  };
}
