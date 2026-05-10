{ lib, ... }:
{
  options.addr = lib.mkOption {
    type = lib.types.str;
    description = "Host IP address or hostname.";
  };

  options.system = lib.mkOption {
    type = lib.types.str;
    description = "Target system architecture.";
  };

  options.role = lib.mkOption {
    type = lib.types.str;
    description = "Host role (web, db, worker, …).";
  };

  config.system = lib.mkDefault "x86_64-linux";
}
