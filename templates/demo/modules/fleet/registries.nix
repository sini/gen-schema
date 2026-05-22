# Instance registries with derive hooks.
#
# Demonstrates:
# - Plain derive: deterministic UID assignment from id_hash
# - User override: explicit uid on an instance skips auto-assignment
# - deriveEither + either: computed endpoint strings from host ref + port
{
  lib,
  config,
  schemaLib,
  gen,
  ...
}:
let
  inherit (schemaLib) mkInstanceRegistry ref;
  inherit (gen) either;

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

  idFromHash =
    { min, max }:
    hash:
    let
      raw = hexToInt (builtins.substring 0 8 hash);
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
  options.fleet.hosts = mkInstanceRegistry config.schema "host" {
    description = "Fleet host instances.";
  };

  options.fleet.users = mkInstanceRegistry config.schema "user" {
    description = "Fleet user instances.";
    derive = deriveUids {
      min = 1000;
      max = 60000;
    };
  };

  options.fleet.admins = mkInstanceRegistry config.schema "admin-user" {
    description = "Fleet admin user instances (inherits user kind).";
    derive = deriveUids {
      min = 60001;
      max = 65000;
    };
  };

  options.fleet.services = mkInstanceRegistry config.schema "service" {
    description = "Fleet service instances.";
    # Deferred ref: bind "host" kind-ref to the hosts registry
    refs.host = config.fleet.hosts;
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
            type = lib.types.nullOr (ref config.fleet.services);
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
}
