{
  inputs = {
    gen-harness.url = "github:sini/gen-harness";
    gen-prelude.url = "github:sini/gen-prelude";
    gen-types.url = "github:sini/gen-types";
    gen-merge.url = "github:sini/gen-merge";
    gen-algebra.url = "github:sini/gen-algebra";
    gen-identity.url = "github:sini/gen-identity";
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
      genSchema = import ../lib {
        inherit prelude;
        merge = genMerge;
        algebra = genAlgebra;
        identity = genIdentity;
      };
    in
    gen-harness.lib.mkCi {
      inherit inputs;
      name = "gen-schema";
      testModules = ./tests;
      specialArgs = {
        inherit
          genIdentity
          genSchema
          genMerge
          genTypes
          genAlgebra
          prelude
          ;
      };
    };
}
