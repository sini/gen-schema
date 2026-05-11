# User instances.
{ ... }:
{
  fleet.users.tux = {
    userName = "tux";
    shell = "/bin/zsh";
  };

  fleet.users.yeti = {
    userName = "yeti";
    # shell defaults to /bin/bash
  };
}
