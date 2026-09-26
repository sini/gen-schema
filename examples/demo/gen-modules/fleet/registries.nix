# Instance registries with derive hooks.
#
# Demonstrates:
# - Plain derive: deterministic UID assignment from id_hash
# - User override: explicit uid on an instance skips auto-assignment
# - deriveEither + either: computed endpoint strings from host ref + port
{
  lib,
  config,
  genSchema,
  genAlgebra,
  ...
}:
let
  inherit (genSchema) mkInstanceRegistry declarationOf evalSchema;
  inherit (genAlgebra) either;

  # The frozen kind set. Kind declarations that used to reach `config.schema.<k>` through this
  # tree's own recursive `config` (the crossing this migration retires) are applied directly here
  # and staged through `evalSchema`, gen-schema's own inheritance pass — the same files, still
  # walked by the outer `gen.tree` unchanged, now ALSO composed as a self-contained pass so
  # admin-user's `inherits = [ "user" ]` resolves through real staged injection rather than a bare
  # read of this tree's own in-flight `config`.
  schema = evalSchema {
    modules = [
      (import ../schema/host.nix { inherit lib; })
      (import ../schema/user.nix { inherit lib; })
      (import ../schema/group.nix { inherit lib genSchema; })
      (import ../schema/network.nix { inherit lib genSchema; })
      (import ../schema/service.nix { inherit lib genSchema; })
      (import ../schema/admin-user.nix { inherit lib; })
      (import ../schema/field-validators.nix { inherit genSchema; })
      (import ../schema/monitoring-plugin.nix { inherit lib; })
      (import ./derived.nix { inherit lib; })
      (import ./methods.nix { inherit lib config genSchema; })
      (import ./validation.nix { inherit lib genSchema; })
    ];
  };

  # --- UID assignment helpers ---

  hexToInt =
    s:
    let
      hexChars = {
        "0" = 0;
        "1" = 1;
        "2" = 2;
        "3" = 3;
        "4" = 4;
        "5" = 5;
        "6" = 6;
        "7" = 7;
        "8" = 8;
        "9" = 9;
        "a" = 10;
        "b" = 11;
        "c" = 12;
        "d" = 13;
        "e" = 14;
        "f" = 15;
      };
    in
    lib.foldl' (acc: c: acc * 16 + hexChars.${c}) 0 (lib.stringToCharacters s);

  # An identity is `"<kind>:" + sha256(<pairs preimage>)` — the kind tag rides OUTSIDE the digest and
  # is recoverable by splitting on the FIRST colon, which is well defined because the mint refuses `:`
  # in a kind name (`gen-schema/lib/identity.nix`, `hashIdentity`). A derived UID wants the digest
  # region, which is the kind-INDEPENDENT half.
  #
  # Slicing the digest out is legitimate HERE and nowhere near an identity comparison: the identity is
  # the WHOLE STRING, so `hashesDiffer` below compares un-sliced values. This slice feeds a derivation,
  # not an equality.
  #
  # The no-colon form is REFUSED rather than tolerated. Accepting it would mean silently deriving from
  # a whole legacy identity when this tree is pinned to a mint that predates the kind join — different
  # UIDs, no signal. A throw names the pin instead.
  digestOf =
    identity:
    let
      parts = builtins.match "[^:]*:(.*)" identity;
    in
    if parts == null then
      throw "identity '${identity}' carries no kind tag: expected \"<kind>:<sha256>\" from gen-schema's mint. A pin predating the kind join derives different values silently, so it is refused here."
    else
      builtins.head parts;

  idFromHash =
    { min, max }:
    hash:
    let
      raw = hexToInt (builtins.substring 0 8 (digestOf hash));
    in
    min + lib.mod raw (max - min);

  # Deterministic ID assignment. Collisions are errors — use explicit
  # uid overrides to resolve them instead of silent probing.
  # initialTaken: { "slot" = "instance-name"; } — pre-occupied slots from explicit UIDs.
  assignIdsWithTaken =
    range: initialTaken: instances:
    let
      sorted = lib.sort (a: b: a < b) (lib.attrNames instances);
    in
    (lib.foldl'
      (
        acc: name:
        let
          slot = idFromHash range instances.${name}.id_hash;
          slotStr = toString slot;
          collision = acc.taken.${slotStr} or null;
        in
        if collision != null then
          throw "UID collision: '${name}' and '${collision}' both hash to ${slotStr}. Fix: set an explicit uid on one of them."
        else
          {
            taken = acc.taken // {
              ${slotStr} = name;
            };
            ids = acc.ids // {
              ${name} = slot;
            };
          }
      )
      {
        taken = initialTaken;
        ids = { };
      }
      sorted
    ).ids;

  # Derive hook: assign UIDs, respecting explicit overrides.
  # Instances with uid != null keep their value. The rest get computed UIDs
  # from id_hash. Collisions error — use explicit uid to resolve.
  deriveUids =
    range: instances:
    let
      explicit = lib.filterAttrs (_: u: u.uid != null) instances;
      auto = lib.filterAttrs (_: u: u.uid == null) instances;
      # Pre-taken: map slot → instance name (for collision error messages)
      taken = lib.mapAttrs' (_: u: {
        name = toString u.uid;
        value = u.name;
      }) explicit;
      computed = assignIdsWithTaken range taken auto;
    in
    lib.mapAttrs (name: user: if user.uid != null then { } else { uid = computed.${name}; }) instances;

  # --- Endpoint derivation via Either pipeline ---

  mkEndpoint =
    service:
    either.pipe [
      (
        s:
        either.right {
          addr = s.host.addr;
          inherit (s) port protocol;
        }
      )
      (
        {
          addr,
          port,
          protocol,
        }:
        either.right "${protocol}://${addr}:${toString port}"
      )
    ] service;
in
{
  # Republish the frozen, inheritance-aware `schema` above for readers OUTSIDE the declaration
  # plane (e.g. `modules/outputs.nix`'s introspection: `_kindNames`, per-kind `.options`,
  # `renderDocs`, `mkCodec`). `options.schema` (`../schema.nix`) is the outer `gen.tree`'s plain
  # merge over the same kind files and does NOT resolve `inherits` (den-hoag
  # examples-demo-outer-merge-introspection-k1sf7) — admin-user's `inherits = [ "user" ]` never
  # reaches it, so a reader of `options.schema.admin-user.options` sees only admin-user's own two
  # fields instead of the five the inheritance-aware kind actually has.
  #
  # `types.raw` + a plain `default` (never `config.frozenSchema = schema`) because `schema` is
  # already a fully-evaluated value, not a set of module defs: assigning it as a CONFIG
  # DEFINITION onto an `mkSchemaOption`-typed option re-enters that option's own internal
  # collection/readOnly bookkeeping and breaks it — measured (candidate rejected): `_kindNames`,
  # `_edges`, `_topology`, `_roots`, `_leaves` come back `«error: … is read-only, but it is
  # defined 2 times»`, and list-valued collections like `validators` silently double (2 → 4),
  # both because the per-file kind declarations still ALSO define the SAME option through the
  # outer merge. A bare `default` on an independent option has exactly one source of truth.
  options.frozenSchema = lib.mkOption {
    type = lib.types.raw;
    readOnly = true;
    default = schema;
    description = "The evalSchema-staged, inheritance-aware schema tree that fleet's registries above are built from -- what introspection and doc/codec generation should read instead of the outer-merge `options.schema`.";
  };

  options.fleet.hosts = mkInstanceRegistry schema.host {
    description = "Fleet host instances.";
  };

  options.fleet.users = mkInstanceRegistry schema.user {
    description = "Fleet user instances.";
    derive = deriveUids {
      min = 1000;
      max = 60000;
    };
  };

  options.fleet.admins = mkInstanceRegistry schema.admin-user {
    description = "Fleet admin user instances (inherits user kind).";
    derive = deriveUids {
      min = 60001;
      max = 65000;
    };
  };

  options.fleet.services = mkInstanceRegistry schema.service {
    description = "Fleet service instances.";
    # Deferred ref: bind "host" kind-ref to the hosts registry
    refs.host = config.fleet.hosts;
    refs.replicas = config.fleet.hosts;
    deriveEither = {
      derive =
        services:
        let
          results = lib.mapAttrs (_: mkEndpoint) services;
          errors = lib.filterAttrs (_: r: r ? left) results;
        in
        if errors == { } then
          { right = lib.mapAttrs (_: r: { endpoint = r.right; }) results; }
        else
          { left = lib.mapAttrsToList (name: r: "${name}: ${r.left}") errors; };
    };
    extraModules = [
      (
        { ... }:
        {
          # Direct ref: upstream is optional self-reference, registry in scope
          options.upstream = lib.mkOption {
            type = lib.types.nullOr (declarationOf config.fleet.services);
            default = null;
            description = "Upstream service this proxies to (direct ref).";
          };
          options.endpoint = lib.mkOption {
            type = lib.types.str;
            readOnly = true;
            internal = true;
            description = "Computed endpoint URL from host addr + port + protocol.";
          };
        }
      )
    ];
  };

  options.fleet.groups = mkInstanceRegistry schema.group {
    description = "Fleet host group instances.";
    refs.members = config.fleet.hosts;
  };

  options.fleet.networks = mkInstanceRegistry schema.network {
    description = "Fleet network instances.";
  };
}
