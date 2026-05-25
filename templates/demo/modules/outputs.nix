# Expose fleet data as flake outputs for demonstration.
{
  lib,
  config,
  schemaLib,
  gen,
  demoMixins,
  ...
}:
let
  inherit (config) fleet;
  record = gen.pure.record;
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
      inherit (config.schema) _kindNames;
      hostOptionCount = builtins.length (config.schema._kindMeta "host").optionNames;
      adminOptionCount = builtins.length (config.schema._kindMeta "admin-user").optionNames;

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

      # --- Refinement contracts (Findler & Felleisen 2002) ---
      # Values that pass through refinement predicates co-located with types.
      managementCidr = fleet.networks.management.cidr;
      managementVlan = fleet.networks.management.vlan;
      managementMtu = fleet.networks.management.mtu;
      productionVlan = fleet.networks.production.vlan;
      productionMtuDefault = fleet.networks.production.mtu;
      networkNames = builtins.attrNames fleet.networks;

      # --- Row-polymorphic validators (Leijen 2005) ---
      # The https-port validator fires only on kinds with both "port" and "protocol".
      # It silently skips kinds (host, user, network) that lack those fields.
      serviceValidatorCount = builtins.length config.schema.service.validators;

      # --- Topology introspection ---
      topologyHost = config.schema._topology.host;
      topologyNetwork = config.schema._topology.network;
      networkOptionCount = builtins.length (config.schema._kindMeta "network").optionNames;
      networkHasNoParent = config.schema._topology.network.parent == null;
      edgeCount = builtins.length config.schema._edges;
      schemaRoots = config.schema._roots;
      schemaLeaves = config.schema._leaves;

      # --- First-class mixins (Bracha & Cook 1990) ---
      # Exercise mixin primitives directly on record-algebra records.
      mixinDemo =
        let
          # Build a base record with a "port" field (required by monitorable mixin)
          baseRecord = record.fromAttrs {
            port = lib.mkOption {
              type = lib.types.int;
              default = 8080;
            };
            name = lib.mkOption {
              type = lib.types.str;
              default = "demo";
            };
          };

          # Apply monitorable mixin: adds metricsPort, metricsPath
          withMonitorable = schemaLib.applyMixin demoMixins.monitorable baseRecord "demo-kind";

          # Apply composed mixin (monitorable + beta(tlsBase))
          withEnhanced = schemaLib.applyMixin demoMixins.enhanced baseRecord "demo-kind";
        in
        {
          # Mixin metadata
          monitorableRequires = demoMixins.monitorable.requires;
          monitorableProvides = demoMixins.monitorable.provides;
          enhancedRequires = demoMixins.enhanced.requires;
          enhancedProvides = demoMixins.enhanced.provides;

          # Record labels after mixin application
          withMonitorableLabels = record.labels withMonitorable;
          withEnhancedLabels = record.labels withEnhanced;
        };

      # --- Blame (structured field-level errors) ---
      blameDemo =
        let
          portBlame = schemaLib.blame "port" "invalid port number";
          addrBlame = schemaLib.blame "addr" "must be a valid IP address";
        in
        {
          portField = portBlame.field;
          portMessage = portBlame.message;
          isBlame = portBlame.__blame;
          addrField = addrBlame.field;
        };
    };

    # --- Documentation generation ---
    docs = schemaLib.renderDocs config.schema;
  };
}
