# Instance registries with derive hooks.
{ lib, config, schemaLib, bend, ... }:
let
  inherit (schemaLib) mkInstanceRegistry mkRefType;
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

  assignIds = range: instances:
    let sorted = lib.sort (a: b: a < b) (lib.attrNames instances);
    in (lib.foldl' (acc: name:
      let
        want = idFromHash range instances.${name}.id_hash;
        probe = slot:
          if !(acc.taken ? ${toString slot}) then slot
          else probe (range.min + lib.mod (slot - range.min + 1) (range.max - range.min));
        assigned = probe want;
      in {
        taken = acc.taken // { ${toString assigned} = true; };
        ids = acc.ids // { ${name} = assigned; };
      }
    ) { taken = {}; ids = {}; } sorted).ids;

  # Bend lens: extract host addr + service port into an endpoint string.
  # focus extracts the relevant fields, parse refines into the endpoint string.
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
    derive = users:
      let uids = assignIds { min = 1000; max = 60000; } users;
      in lib.mapAttrs (name: _: { uid = uids.${name}; }) users;
  };

  options.fleet.admins = mkInstanceRegistry config.schema "admin-user" {
    description = "Fleet admin user instances (inherits user kind).";
    derive = admins:
      let uids = assignIds { min = 60001; max = 65000; } admins;
      in lib.mapAttrs (name: _: { uid = uids.${name}; }) admins;
  };

  options.fleet.services = mkInstanceRegistry config.schema "service" {
    description = "Fleet service instances.";
    # deriveEither with bend: compute endpoint strings from host ref + port.
    # Port validation is handled by schema.service.validators (in validation.nix).
    deriveEither = {
      derive = services:
        let
          result = (bend.eachValue mkEndpoint).get services;
        in
        if result ? right then
          { right = lib.mapAttrs (_: endpoint: { inherit endpoint; }) result.right; }
        else
          result;
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
