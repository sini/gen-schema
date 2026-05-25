# Network kind: demonstrates refinement contracts (Findler & Felleisen 2002).
# Inline predicates co-located with type declarations (Rondon 2008).
{ lib, schemaLib, ... }:
{
  config.schema.network = {
    options.cidr = lib.mkOption {
      type = schemaLib.refined lib.types.str {
        check = self: builtins.match "([0-9]+\\.){3}[0-9]+/[0-9]+" self != null;
        message = "must be a valid CIDR (e.g. 10.0.0.0/24)";
      };
      description = "Network CIDR block.";
    };
    options.vlan = lib.mkOption {
      type = schemaLib.refined lib.types.int [
        {
          check = self: self > 0;
          message = "must be positive";
        }
        {
          check = self: self < 4095;
          message = "must be < 4095";
        }
      ];
      description = "VLAN ID (composed refinements -- both must pass).";
    };
    options.mtu = lib.mkOption {
      type = schemaLib.refined lib.types.int {
        check = self: self >= 1280 && self <= 9000;
        message = "MTU must be 1280-9000";
        lazy = true;
      };
      default = 1500;
      description = "MTU (lazy contract -- validated at access time, not pipeline time).";
    };
  };
}
