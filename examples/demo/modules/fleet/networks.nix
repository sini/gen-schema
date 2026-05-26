# Network instances with refinement contracts.
# Invalid values (e.g. vlan = 0, cidr without slash) would be caught
# by the refinement predicates declared on the network kind.
_: {
  fleet.networks.management = {
    cidr = "10.0.0.0/24";
    vlan = 100;
    mtu = 9000;
  };
  fleet.networks.production = {
    cidr = "10.0.1.0/24";
    vlan = 200;
    # mtu defaults to 1500 (lazy contract -- validated at access time)
  };
}
