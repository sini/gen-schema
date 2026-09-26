# Expose fleet data as flake outputs for demonstration.
#
# READER side of the hub's value-injection split (ADR-0031 F1: rehomed from gen-flake, marked
# INTERIM). The gen module tree is composed PURELY by the hub's `flakeModules.default`
# (`gen.tree = ./gen-modules`), which injects the resolved config VALUES as the `genValues`
# module arg into every flake module. This reader consumes those injected values — NOT a flake-parts
# `fleet`/`schema` OPTION tree — so no gen TYPE ever enters the flake-parts options tree (the
# `substSubModules`/`getSubOptions` throw the old `options.schema = mkSchemaOption {}` embed caused).
#
# `genSchema`/`genAlgebra` are the gen libraries (provided as flake-parts `_module.args` in flake.nix);
# they are used here only to RENDER over the injected values (renderDocs/mkCodec/blame) and to exercise
# the mixin API — reading `.type.name` etc. as inert data, never re-embedding a gen type as an option.
{
  lib,
  genValues,
  genSchema,
  genAlgebra,
  ...
}:
let
  # `frozenSchema`, not `genValues.schema`: the latter is the outer `gen.tree`'s plain merge and
  # does not resolve `inherits` (den-hoag examples-demo-outer-merge-introspection-k1sf7). The
  # introspection/docs/codec reads below want the SAME evalSchema-staged, inheritance-aware view
  # `fleet`'s registries are built from — `gen-modules/fleet/registries.nix` republishes it.
  inherit (genValues) fleet frozenSchema;
  record = genAlgebra.record;
  demoMixins = import ./demo-mixins.nix { inherit lib genSchema genAlgebra; };
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

      # --- Cross-instance references (schema.declarationOf) ---
      # Deferred ref: host declared as declarationOf "host" on service kind, bound via refs
      nginxHost = fleet.services.nginx.host.name;
      nginxHostAddr = fleet.services.nginx.host.addr;
      postgresHost = fleet.services.postgres.host.name;

      # Direct ref: upstream declared as declarationOf config.fleet.services in extraModules
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
      inherit (frozenSchema) _kindNames;
      hostOptionCount = builtins.length (builtins.attrNames frozenSchema.host.options);
      adminOptionCount = builtins.length (builtins.attrNames frozenSchema.admin-user.options);

      # Guards `adminOptionCount` (and every other read above) against silently sliding back onto
      # `genValues.schema` (the outer `gen.tree` merge, which does not resolve `inherits`) --
      # exactly the regression den-hoag examples-demo-outer-merge-introspection-k1sf7 measured:
      # `adminOptionCount` read 2, not 5, because admin-user's `inherits = [ "user" ]` never
      # reached that merge. Checked STRUCTURALLY rather than against a pinned count, so it holds
      # regardless of how many fields either kind declares: for every kind with a nonempty
      # `inherits`, its `.options` must be a superset of each parent's `.options`. Forced by
      # `nix eval .#fleet` (the row's own oracle), which prints every leaf of this attrset.
      schemaInheritanceGuard =
        let
          violations = lib.concatMap (
            k:
            let
              ownOpts = builtins.attrNames frozenSchema.${k}.options;
              parents = frozenSchema.${k}.inherits or [ ];
            in
            lib.concatMap (
              p:
              let
                missing = builtins.filter (o: !(builtins.elem o ownOpts)) (
                  builtins.attrNames frozenSchema.${p}.options
                );
              in
              lib.optional (missing != [ ]) "'${k}' inherits '${p}' but is missing option(s): ${toString missing}"
            ) parents
          ) frozenSchema._kindNames;
        in
        if violations != [ ] then
          throw ''
            gen-schema examples/demo: schema inheritance is not resolved in `frozenSchema` --
            ${lib.concatStringsSep "\n            " violations}
            This is the outer-merge-vs-frozen-schema regression den-hoag
            examples-demo-outer-merge-introspection-k1sf7 fixed. Check that `outputs.nix` and
            `gen-modules/fleet/registries.nix` still read the `evalSchema`-staged `frozenSchema`
            option, not `genValues.schema` (the outer `gen.tree`'s plain merge).''
        else
          true;

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

      # --- Refinement contracts (§ Findler 2002) ---
      # Values that pass through refinement predicates co-located with types.
      managementCidr = fleet.networks.management.cidr;
      managementVlan = fleet.networks.management.vlan;
      managementMtu = fleet.networks.management.mtu;
      productionVlan = fleet.networks.production.vlan;
      productionMtuDefault = fleet.networks.production.mtu;
      networkNames = builtins.attrNames fleet.networks;

      # --- Row-polymorphic validators (§ Leijen 2005) ---
      # The https-port validator fires only on kinds with both "port" and "protocol".
      # It silently skips kinds (host, user, network) that lack those fields.
      serviceValidatorCount = builtins.length frozenSchema.service.validators;

      # --- Topology introspection ---
      topologyHost = frozenSchema._topology.host;
      topologyNetwork = frozenSchema._topology.network;
      networkOptionCount = builtins.length (builtins.attrNames frozenSchema.network.options);
      networkHasNoParent = frozenSchema._topology.network.parent == null;
      edgeCount = builtins.length frozenSchema._edges;
      schemaRoots = frozenSchema._roots;
      schemaLeaves = frozenSchema._leaves;

      # --- First-class mixins (§ Bracha 1990) ---
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
          withMonitorable = genSchema.applyMixin demoMixins.monitorable baseRecord "demo-kind";

          # Apply composed mixin (monitorable + beta(tlsBase))
          withEnhanced = genSchema.applyMixin demoMixins.enhanced baseRecord "demo-kind";
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

      # --- Codec (serialization) ---
      codecDemo =
        let
          hostCodec = genSchema.mkCodec frozenSchema.host {
            fields = {
              # Exclude metricsPort from serialization
              metricsPort = {
                exclude = true;
              };
              monitored = {
                exclude = true;
              };
            };
          };
          serviceCodec = genSchema.mkCodec frozenSchema.service { };

          # Encode a single instance
          encodedIgloo = hostCodec.encode fleet.hosts.igloo;

          # JSON round-trip
          jsonStr = hostCodec.json.serialize fleet.hosts.igloo;
          roundTripped = hostCodec.json.deserialize jsonStr;

          # Encode all instances
          allHosts = hostCodec.encodeAll fleet.hosts;

          # Service codec: ref fields auto-encode to name strings
          encodedNginx = serviceCodec.encode fleet.services.nginx;

          # Type-registered codec: register an encoder keyed by type name.
          # The int encoder fires on every field whose type is `int` — here
          # the host's metricsPort (contributed by the monitoring plugin).
          typeCodec = genSchema.mkCodec frozenSchema.host {
            types = {
              int = {
                encode = v: "port:${toString v}";
              };
            };
          };
          typeEncodedPort = (typeCodec.encode fleet.hosts.igloo).metricsPort;
        in
        {
          # Basic encode strips internals (name, id_hash, methods)
          encodedIglooKeys = builtins.attrNames encodedIgloo;
          iglooHasName = encodedIgloo ? name;
          iglooHasIdHash = encodedIgloo ? id_hash;

          # Excluded fields are absent
          iglooHasMetricsPort = encodedIgloo ? metricsPort;

          # JSON round-trip produces registry-compatible attrset
          roundTrippedAddr = roundTripped.addr;

          # Encode all
          allHostNames = builtins.attrNames allHosts;

          # Ref fields encode to name strings
          nginxHostRef = encodedNginx.host;

          # Type-registered codec
          iglooPortEncoded = typeEncodedPort;
        };

      # --- Blame (structured field-level errors) ---
      blameDemo =
        let
          portBlame = genSchema.blame "port" "invalid port number";
          addrBlame = genSchema.blame "addr" "must be a valid IP address";
        in
        {
          portField = portBlame.field;
          portMessage = portBlame.message;
          isBlame = portBlame.__blame;
          addrField = addrBlame.field;
        };
    };

    # --- Documentation generation ---
    docs = genSchema.renderDocs frozenSchema;
  };
}
