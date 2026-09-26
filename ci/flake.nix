{
  inputs = {
    gen-harness.url = "github:sini/gen-harness";
    gen-prelude.url = "github:sini/gen-prelude";
    gen-types.url = "github:sini/gen-types";
    gen-merge.url = "github:sini/gen-merge";
    gen-algebra.url = "github:sini/gen-algebra";
    gen-identity.url = "github:sini/gen-identity";
    gen-graph.url = "github:sini/gen-graph";
    gen-graph.inputs.gen-prelude.follows = "gen-prelude";
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
  };

  outputs =
    inputs@{
      gen-harness,
      nixpkgs,
      gen-prelude,
      gen-types,
      gen-merge,
      gen-algebra,
      gen-identity,
      ...
    }:
    let
      inherit (nixpkgs) lib;
      prelude = gen-prelude.lib;
      genTypes = gen-types.lib;
      genMerge = gen-merge.lib;
      genAlgebra = gen-algebra.lib;
      genIdentity = gen-identity.lib;
      genGraph = inputs.gen-graph.lib;
      genSchema = import ../lib {
        inherit prelude;
        graph = genGraph;
        merge = genMerge;
        algebra = genAlgebra;
        identity = genIdentity;
      };
    in
    gen-harness.lib.mkCi {
      inherit inputs;
      name = "gen-schema";
      testModules = ./tests;
      # The SECOND output, `nix-unit --flake ./ci#testsError`. `mkCi`'s `checks.default` asserter
      # quantifies over `flake.tests` and evaluates every cell's `expr` unconditionally, so a cell
      # with a throwing `expr` crashes that gate instead of failing it — which is why a refusal whose
      # MESSAGE is the subject cannot live under `./tests`. `tryEval` discards the message
      # (`{ success = false; value = false; }`), so the cells that assert WHICH refusal fired have
      # nowhere else to go. Same wiring as gen-merge's and gen-memo's.
      extraModules = [
        ./tests-error.nix
        # `ref` is a TOMBSTONE (lib/ref.nix, THE RETIRED NAME; den-hoag-2zjg1): `checks.root-surface`
        # excludes it from the walk, and the generated `root-surface-retired.test-retired-ref` cell pins
        # this exact message at the root seam, so a resurrected or reworded tombstone reds.
        {
          gen.ci.rootSurface.retired.ref =
            "gen-schema: `ref` is renamed `declarationOf`. A value denoting a node is a declaration and the name written at a use site is a reference (Neron et al. 2015), so the type of a field holding either is `declarationOf <kind-or-registry>`; the argument and the behaviour are unchanged.";
        }
      ];
      specialArgs = {
        inherit
          genIdentity
          genGraph
          genSchema
          genMerge
          genTypes
          genAlgebra
          prelude
          ;
      };
    };
}
