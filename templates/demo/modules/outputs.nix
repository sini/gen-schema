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

      # --- Cross-instance references (schema.ref) ---
      # Deferred ref: host declared as ref "host" on service kind, bound via refs
      nginxHost = fleet.services.nginx.host.name;
      nginxHostAddr = fleet.services.nginx.host.addr;
      postgresHost = fleet.services.postgres.host.name;

      # Direct ref: upstream declared as ref config.fleet.services in extraModules
      gatewayUpstreamPort = fleet.services.gateway.upstream.port;
      gatewayUpstreamIsNginx = fleet.services.gateway.upstream.name == "nginx";
      standaloneUpstreamNull = fleet.services.nginx.upstream == null;

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

      # --- Kind mix-in composition ---
      # admin-user imports user kind — gets userName, shell for free
      adminNames = builtins.attrNames fleet.admins;
      rootShell = fleet.admins.root.shell;
      rootSudo = fleet.admins.root.sudoPrivileges;
      rootSshKeyCount = builtins.length fleet.admins.root.sshKeys;
      deployUserName = fleet.admins.deploy.userName;
      deploySudo = fleet.admins.deploy.sudoPrivileges;

      # admin-user and user have independent identity hashes (different kind prefix)
      rootHash = fleet.admins.root.id_hash;
      tuxHash = fleet.users.tux.id_hash;
      hashesDiffer = fleet.admins.root.id_hash != fleet.users.tux.id_hash;

      # --- Introspection ---
      kindNames = config.schema._meta.kindNames;
      hostOptionCount = builtins.length (config.schema._meta.kindMeta "host").optionNames;
      adminOptionCount = builtins.length (config.schema._meta.kindMeta "admin-user").optionNames;

      # --- Derive hooks ---
      # Deterministic UIDs from id_hash (auto-assigned)
      tuxUid = fleet.users.tux.uid;
      yetiUid = fleet.users.yeti.uid;
      uidsDiffer = fleet.users.tux.uid != fleet.users.yeti.uid;

      # Explicit override — service-account keeps uid 999
      serviceAccountUid = fleet.users.service-account.uid;
      overridePreserved = fleet.users.service-account.uid == 999;

      # Admin UIDs in a separate range
      rootUid = fleet.admins.root.uid;
      adminUidRange = fleet.admins.root.uid >= 60001;

      # --- Derive + Either ---
      # Computed endpoint from either pipeline (host addr + port + protocol)
      nginxEndpoint = fleet.services.nginx.endpoint;
      postgresEndpoint = fleet.services.postgres.endpoint;
      gatewayEndpoint = fleet.services.gateway.endpoint;
    };

    # --- Documentation generation ---
    docs = schemaLib.renderDocs config.schema;
  };
}
