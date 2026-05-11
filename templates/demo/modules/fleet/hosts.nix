# Host instances.
{ ... }:
{
  fleet.hosts.igloo = {
    addr = "10.0.1.1";
    role = "web";
    # system defaults to x86_64-linux
  };

  fleet.hosts.iceberg = {
    addr = "10.0.2.1";
    role = "db";
    system = "aarch64-linux";
  };
}
