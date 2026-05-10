{
  lib,
  schemaLib,
  config,
  ...
}:
let
  inherit (schemaLib) mkInstanceRegistry mkRefType;
in
{
  options.hosts = mkInstanceRegistry config.schema "host" {
    description = "Fleet host instances.";
  };

  options.users = mkInstanceRegistry config.schema "user" {
    description = "Fleet user instances.";
  };

  options.services = mkInstanceRegistry config.schema "service" {
    description = "Fleet service instances.";
    extraModules = [
      (
        { ... }:
        {
          options.host = lib.mkOption {
            type = mkRefType config.hosts;
            description = "Host this service runs on (reference by name).";
          };
        }
      )
    ];
  };

  config.hosts.igloo = {
    addr = "10.0.1.1";
    role = "web";
    # system takes the default: x86_64-linux
  };

  config.hosts.iceberg = {
    addr = "10.0.2.1";
    role = "db";
    system = "aarch64-linux";
  };

  config.users.tux = {
    userName = "tux";
    shell = "/bin/zsh";
  };

  config.users.yeti = {
    userName = "yeti";
    # shell takes the default: /bin/bash
  };

  config.services.nginx = {
    host = "igloo";
    port = 80;
  };

  config.services.postgres = {
    host = "iceberg";
    port = 5432;
  };
}
