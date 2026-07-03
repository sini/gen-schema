{
  inputs = {
    gen.url = "github:sini/gen";
    gen-prelude.url = "github:sini/gen-prelude";
    gen-types.url = "github:sini/gen-types";
    gen-merge.url = "github:sini/gen-merge";
    gen-algebra.url = "github:sini/gen-algebra";
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
  };

  outputs =
    inputs@{
      gen,
      nixpkgs,
      gen-prelude,
      gen-types,
      gen-merge,
      gen-algebra,
      ...
    }:
    let
      inherit (nixpkgs) lib;
      prelude = gen-prelude.lib;
      genTypes = gen-types.lib;
      genMerge = gen-merge.lib;
      genAlgebra = gen-algebra.lib;
      genSchema = import ../lib {
        inherit prelude;
        merge = genMerge;
        algebra = genAlgebra;
      };
    in
    gen.lib.mkCi {
      inherit inputs;
      name = "gen-schema";
      testModules = ./tests;
      specialArgs = {
        inherit
          genSchema
          genMerge
          genTypes
          genAlgebra
          prelude
          ;
      };
    };
}
