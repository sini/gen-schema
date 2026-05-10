{
  lib,
  schemaLib,
  config,
  ...
}:
let
  inherit (schemaLib) mkInstanceRegistry;
in
{
  options.hosts = mkInstanceRegistry config.schema "host" {
    description = "Fleet host instances.";
  };

  options.users = mkInstanceRegistry config.schema "user" {
    description = "Fleet user instances.";
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
}
