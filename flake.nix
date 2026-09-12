{
  description = "gen-schema: typed record registry with extension points for the pure-gen module system";

  # Class layering: gen-prelude → gen-types → gen-merge → gen-schema. The library (./lib) is
  # nixpkgs-lib-free (checked by ci/tests/purity.nix): it drives the registry engine on gen-merge's
  # byte-mode evalModuleTree + gen-types leaf checkers, NOT lib.evalModules / lib.types. nixpkgs is
  # pulled ONLY in ci/ (the nix-unit harness + any non-schema `lib.*` the test corpus still uses).
  #
  # gen-types is reached THROUGH gen-merge and is not declared here. It was, and gen-schema called
  # it zero times: the library entry takes { prelude, merge, algebra } and gen-types was never
  # injected into it. A declared-but-uncalled input is a false coupling fact — an edge the hub's
  # direction-of-dependence lint reads, ranks and reports for a dependence that does not exist —
  # so the declaration is gen-merge's to make, from gen-merge's own lock.
  inputs = {
    gen-prelude.url = "github:sini/gen-prelude";
    gen-merge.url = "github:sini/gen-merge";
    gen-algebra.url = "github:sini/gen-algebra";
    # The one minting authority, now its own dependency-free leaf. gen-schema keeps the
    # identity REFLECTION half — which of a kind's options are identity keys, and stamping
    # id_hash — and builds values WITH the injected mint inside its own evaluation, which is
    # ADR-0014's constructing arm rather than a re-hand.
    gen-identity.url = "github:sini/gen-identity";
  };

  outputs =
    {
      gen-prelude,
      gen-merge,
      gen-algebra,
      gen-identity,
      ...
    }:
    {
      # `nix flake check` forces the WHNF of every top-level output and nothing deeper, so this root's
      # green quantified over the `lib` SPINE alone: a member of the published surface could throw and
      # the check still exited 0 (measured — den-hoag-z1ta6). Hanging the force on that spine is what
      # makes the green mean "the surface evaluates", and a library needs no new output name for it.
      # The depth is each member's WHNF and no deeper: a retirement tombstone is a published `throw`
      # by design (gen-scope's `buildNodes`), so a deep force is red on a healthy tree.
      lib =
        let
          surface = import ./lib {
            prelude = gen-prelude.lib;
            merge = gen-merge.lib;
            algebra = gen-algebra.lib;
            identity = gen-identity.lib;
          };
        in
        builtins.deepSeq (builtins.mapAttrs (_: builtins.typeOf) surface) surface;
      flakeModules.default = ./flakeModule.nix;
    };
}
