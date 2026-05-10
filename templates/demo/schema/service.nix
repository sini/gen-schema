{ lib, ... }:
{
  options.port = lib.mkOption {
    type = lib.types.int;
    description = "Service port number.";
  };

  options.protocol = lib.mkOption {
    type = lib.types.str;
    description = "Network protocol (tcp, udp, …).";
  };

  config.protocol = lib.mkDefault "tcp";
}
