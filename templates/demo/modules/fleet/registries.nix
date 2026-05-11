# Instance registries: typed attrsOf per kind.
{ lib, config, schemaLib, ... }:
let
  inherit (schemaLib) mkInstanceRegistry mkRefType;
in
{
  options.fleet.hosts = mkInstanceRegistry config.schema "host" {
    description = "Fleet host instances.";
  };

  options.fleet.users = mkInstanceRegistry config.schema "user" {
    description = "Fleet user instances.";
  };

  options.fleet.services = mkInstanceRegistry config.schema "service" {
    description = "Fleet service instances.";
    extraModules = [
      ({ ... }: {
        options.host = lib.mkOption {
          type = mkRefType config.fleet.hosts;
          description = "Host this service runs on (reference by name).";
        };
      })
    ];
  };
}
