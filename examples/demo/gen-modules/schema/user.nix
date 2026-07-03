# User kind: accounts on hosts.
{ lib, ... }:
{
  config.schema.user = {
    options.userName = lib.mkOption {
      type = lib.types.str;
      description = "Unix user name.";
    };
    options.shell = lib.mkOption {
      type = lib.types.str;
      description = "Login shell path.";
      default = "/bin/bash";
    };
  };
}
