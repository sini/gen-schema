# gen-schema byte-parity oracle (C3 refined gate): the RE-HOSTED gen-schema (gen-merge engine) must
# produce byte-identical resolved instances — including the `id_hash` SHA-256 — to the ORIGINAL
# nixpkgs-`lib` gen-schema (main @ 2b7c2d3). A representative schema is driven through BOTH engines
# via a parameterized provider `P`, and the resolved instance data is compared. Mutation-teeth prove
# the oracle discriminates (else "byte-identical" is vacuous). nixpkgs is REFERENCE-side only.
let
  prelude = import /home/sini/Documents/repos/gen-prelude/lib;
  genTypes = import /home/sini/Documents/repos/gen-types/lib { inherit prelude; };
  genMerge = import /home/sini/Documents/repos/gen-merge/lib {
    inherit prelude;
    types = genTypes;
  };
  genAlgebra = import /home/sini/Documents/repos/gen-algebra/lib;
  lib = (builtins.getFlake "nixpkgs").lib;

  # the two gen-schema builds
  gsNew = import ../lib {
    inherit prelude;
    merge = genMerge;
    algebra = genAlgebra;
  };
  gsOrig = import /home/sini/Documents/repos/gen-schema/lib {
    inherit lib;
    algebra = genAlgebra;
  };

  newP = {
    mkOption = genMerge.mkOption;
    types = genMerge.types;
    eval = genMerge.evalModuleTree;
    gs = gsNew;
  };
  origP = {
    inherit (lib) mkOption types;
    eval = lib.evalModules;
    gs = gsOrig;
  };

  # ── representative schema: a `host` kind + 2 instances, port default, id_hash reflection ──
  hostsOf =
    P: addr2:
    let
      eval = P.eval {
        modules = [
          {
            options.schema = P.gs.mkSchemaOption { };
            config.schema.host = {
              options.name = P.mkOption { type = P.types.str; };
              options.addr = P.mkOption { type = P.types.str; };
              options.port = P.mkOption {
                type = P.types.int;
                default = 22;
              };
            };
          }
          {
            options.hosts = P.gs.mkInstanceRegistry eval.config.schema.host { };
            config.hosts.igloo = {
              name = "igloo";
              addr = "10.0.0.1";
              port = 2222;
            };
            config.hosts.yurt = {
              name = "yurt";
              addr = addr2;
            };
          }
        ];
      };
    in
    eval.config.hosts;

  # project the identifying data (incl id_hash SHA) for comparison
  project =
    hosts:
    lib.mapAttrs (_: h: {
      inherit (h)
        name
        addr
        port
        id_hash
        ;
    }) hosts;

  newHosts = project (hostsOf newP "10.0.0.2");
  origHosts = project (hostsOf origP "10.0.0.2");

  # teeth: a mutated instance (different addr) changes the reference id_hash — so an id_hash match
  # across engines is content-meaningful, not a constant.
  origMutated = project (hostsOf origP "10.9.9.9");
in
{
  # BYTE-PARITY: re-hosted instances (name/addr/port/id_hash) == original nixpkgs instances
  parity-instances-byte-identical = newHosts == origHosts;

  # id_hash specifically matches across engines (proves identity-reflection name-fix parity)
  parity-id_hash =
    newHosts.igloo.id_hash == origHosts.igloo.id_hash
    && newHosts.yurt.id_hash == origHosts.yurt.id_hash;

  # TEETH: the oracle can FAIL — mutating an instance changes its id_hash (so the match above is real)
  teeth-mutation-changes-id_hash = origMutated.yurt.id_hash != origHosts.yurt.id_hash;
  # TEETH: and the re-hosted engine tracks that mutation identically
  teeth-mutation-parity = project (hostsOf newP "10.9.9.9") == origMutated;

  # dump for eyeballing
  sample = {
    new = newHosts.igloo;
    orig = origHosts.igloo;
  };
}
