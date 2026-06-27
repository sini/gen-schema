{
  inputs = {
    gen.url = "github:sini/gen";
    gen-algebra.url = "github:sini/gen-algebra";
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
  };

  outputs =
    inputs@{ gen, nixpkgs, ... }:
    let
      inherit (nixpkgs) lib;
      # Flat set (gen-algebra root default ignores its arg and returns `import ./lib`).
      genAlgebra = import "${inputs.gen-algebra}" { inherit lib; };
      genSchema = import ../lib {
        inherit lib;
        algebra = inputs.gen-algebra.lib;
      };
    in
    gen.lib.mkCi {
      inherit inputs;
      name = "gen-schema";
      testModules = ./tests;
      specialArgs = { inherit genSchema genAlgebra; };
    };
}
