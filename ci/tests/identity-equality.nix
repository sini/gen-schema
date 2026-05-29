# Identity equality: instances with the same primitive values should produce
# the same id_hash. Two references to the same instance should be equal
# via id_hash even when structural == might diverge.
{ lib, genSchema, ... }:
let
  inherit (genSchema) mkSchemaOption mkInstanceRegistry;

  eval = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption { };
        options.hosts = mkInstanceRegistry eval.config.schema.host { };
        config.schema.host = {
          options.addr = lib.mkOption { type = lib.types.str; };
          options.role = lib.mkOption {
            type = lib.types.str;
            default = "worker";
          };
        };
        config.hosts.igloo = {
          addr = "10.0.1.1";
          role = "web";
        };
        config.hosts.iceberg = {
          addr = "10.0.2.1";
          role = "db";
        };
      }
    ];
  };

  # Two separate accesses to the same instance
  ref1 = eval.config.hosts.igloo;
  ref2 = eval.config.hosts.igloo;

  # Different instance
  other = eval.config.hosts.iceberg;
in
{
  # Same instance, two references — hashes match
  flake.tests."identity-eq".test-same-instance-same-hash = {
    expr = ref1.id_hash == ref2.id_hash;
    expected = true;
  };
  # Same instance — string equality works as entity comparison
  flake.tests."identity-eq".test-hash-string-comparison = {
    expr = ref1.id_hash;
    expected = ref2.id_hash;
  };
  # Different instances — hashes differ
  flake.tests."identity-eq".test-different-instance-different-hash = {
    expr = ref1.id_hash == other.id_hash;
    expected = false;
  };
  # Filter pattern: find all hosts that aren't igloo
  flake.tests."identity-eq".test-filter-by-hash = {
    expr = lib.attrNames (lib.filterAttrs (_: h: h.id_hash != ref1.id_hash) eval.config.hosts);
    expected = [ "iceberg" ];
  };
  # Membership pattern: check if a host is in a set
  flake.tests."identity-eq".test-membership-by-hash = {
    expr =
      let
        targetHashes = map (h: h.id_hash) [ ref1 ];
      in
      lib.elem other.id_hash targetHashes;
    expected = false;
  };
  flake.tests."identity-eq".test-membership-positive = {
    expr =
      let
        targetHashes = map (h: h.id_hash) [
          ref1
          other
        ];
      in
      lib.elem ref2.id_hash targetHashes;
    expected = true;
  };
}
