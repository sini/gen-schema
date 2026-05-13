# Instance registries with derive hooks and validation.
{
  lib,
  config,
  schemaLib,
  bend,
  ...
}:
let
  inherit (schemaLib) mkInstanceRegistry mkRefType;
  inherit (config._deriveHelpers) assignIds;

  # Bend lens for port validation
  validPort = bend.pipe [
    bend.int
    (bend.satisfy (p: p > 0 && p < 65536))
  ];
in
{
  options.fleet.hosts = mkInstanceRegistry config.schema "host" {
    description = "Fleet host instances.";
  };

  options.fleet.users = mkInstanceRegistry config.schema "user" {
    description = "Fleet user instances.";
    derive =
      users:
      let
        uids = assignIds {
          min = 1000;
          max = 60000;
        } users;
      in
      lib.mapAttrs (name: _: { uid = uids.${name}; }) users;
  };

  options.fleet.admins = mkInstanceRegistry config.schema "admin-user" {
    description = "Fleet admin user instances (inherits user kind).";
    derive =
      admins:
      let
        uids = assignIds {
          min = 60001;
          max = 65000;
        } admins;
      in
      lib.mapAttrs (name: _: { uid = uids.${name}; }) admins;
  };

  options.fleet.services = mkInstanceRegistry config.schema "service" {
    description = "Fleet service instances.";
    deriveEither = {
      derive =
        services:
        let
          portLens = bend.compose (bend.attr "port") validPort;
          result = (bend.eachValue portLens).get services;
        in
        if result ? right then { right = builtins.mapAttrs (_: _: { }) result.right; } else result;
    };
    extraModules = [
      (
        { ... }:
        {
          options.host = lib.mkOption {
            type = mkRefType config.fleet.hosts;
            description = "Host this service runs on (reference by name).";
          };
        }
      )
    ];
  };
}
