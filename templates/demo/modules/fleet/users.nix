# User instances.
{ ... }:
{
  fleet.users.tux = {
    userName = "tux";
    shell = "/bin/zsh";
    # uid computed automatically from id_hash
  };

  fleet.users.yeti = {
    userName = "yeti";
    # shell defaults to /bin/bash
    # uid computed automatically from id_hash
  };

  fleet.users.service-account = {
    userName = "service-account";
    uid = 999; # explicit override — derive skips this, keeps 999
  };
}
