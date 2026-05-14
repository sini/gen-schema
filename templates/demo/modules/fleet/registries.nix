# Instance registries with derive hooks.
#
# Demonstrates:
# - Plain derive: deterministic UID assignment from id_hash
# - User override: explicit uid on an instance skips auto-assignment
# - deriveEither + bend: computed endpoint strings from host ref + port
{ lib, config, schemaLib, bend, ... }:
let
  inherit (schemaLib) mkInstanceRegistry mkRefType;

  # --- UID assignment helpers ---

  hexToInt = s:
    let
      hexChars = {
        "0" = 0; "1" = 1; "2" = 2; "3" = 3;
        "4" = 4; "5" = 5; "6" = 6; "7" = 7;
        "8" = 8; "9" = 9; "a" = 10; "b" = 11;
        "c" = 12; "d" = 13; "e" = 14; "f" = 15;
      };
    in lib.foldl' (acc: c: acc * 16 + hexChars.${c}) 0
      (lib.stringToCharacters s);

  idFromHash = { min, max }: hash:
    let raw = hexToInt (builtins.substring 0 8 hash);
    in min + lib.mod raw (max - min);

  # Deterministic ID assignment. Collisions are errors — use explicit
  # uid overrides to resolve them instead of silent probing.
  # initialTaken: { "slot" = "instance-name"; } — pre-occupied slots from explicit UIDs.
  assignIdsWithTaken = range: initialTaken: instances:
    let
      sorted = lib.sort (a: b: a < b) (lib.attrNames instances);
    in (lib.foldl' (acc: name:
      let
        slot = idFromHash range instances.${name}.id_hash;
        slotStr = toString slot;
        collision = acc.taken.${slotStr} or null;
      in
      if collision != null then
        throw "UID collision: '${name}' and '${collision}' both hash to ${slotStr}. Fix: set an explicit uid on one of them."
      else {
        taken = acc.taken // { ${slotStr} = name; };
        ids = acc.ids // { ${name} = slot; };
      }
    ) { taken = initialTaken; ids = {}; } sorted).ids;

  # Derive hook: assign UIDs, respecting explicit overrides.
  # Instances with uid != null keep their value. The rest get computed UIDs
  # from id_hash. Collisions error — use explicit uid to resolve.
  deriveUids = range: instances:
    let
      explicit = lib.filterAttrs (_: u: u.uid != null) instances;
      auto = lib.filterAttrs (_: u: u.uid == null) instances;
      # Pre-taken: map slot → instance name (for collision error messages)
      taken = lib.mapAttrs' (_: u: { name = toString u.uid; value = u.name; }) explicit;
      computed = assignIdsWithTaken range taken auto;
    in
    lib.mapAttrs (name: user:
      if user.uid != null then {}
      else { uid = computed.${name}; }
    ) instances;

  # --- Bend lens for endpoint derivation ---

  mkEndpoint = bend.pipe [
    (bend.focus
      (s: { addr = s.host.addr; port = s.port; protocol = s.protocol; })
      (_: v: v))
    (bend.parse
      ({ addr, port, protocol, ... }:
        bend.right "${protocol}://${addr}:${toString port}")
      bend.identity)
  ];
in
{
  options.fleet.hosts = mkInstanceRegistry config.schema "host" {
    description = "Fleet host instances.";
  };

  options.fleet.users = mkInstanceRegistry config.schema "user" {
    description = "Fleet user instances.";
    derive = deriveUids { min = 1000; max = 60000; };
  };

  options.fleet.admins = mkInstanceRegistry config.schema "admin-user" {
    description = "Fleet admin user instances (inherits user kind).";
    derive = deriveUids { min = 60001; max = 65000; };
  };

  options.fleet.services = mkInstanceRegistry config.schema "service" {
    description = "Fleet service instances.";
    deriveEither = {
      derive = services:
        let result = (bend.eachValue mkEndpoint).get services;
        in if result ? right then
          { right = lib.mapAttrs (_: endpoint: { inherit endpoint; }) result.right; }
        else result;
    };
    extraModules = [
      ({ ... }: {
        options.host = lib.mkOption {
          type = mkRefType config.fleet.hosts;
          description = "Host this service runs on (reference by name).";
        };
        options.endpoint = lib.mkOption {
          type = lib.types.str;
          readOnly = true;
          internal = true;
          description = "Computed endpoint URL from host addr + port + protocol.";
        };
      })
    ];
  };
}
