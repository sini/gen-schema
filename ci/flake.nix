{
  inputs = {
    gen.url = "github:sini/gen";
    gen-algebra.url = "github:sini/gen-algebra";
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
    flake-parts.follows = "gen/flake-parts";
    flake-root.follows = "gen/flake-root";
    nix-unit.follows = "gen/nix-unit";
    treefmt-nix.follows = "gen/treefmt-nix";
    devshell.follows = "gen/devshell";
    import-tree.follows = "gen/import-tree";
  };

  outputs =
    inputs@{ gen, nixpkgs, ... }:
    let
      inherit (nixpkgs) lib;
      genLib = import "${inputs.gen-algebra}" { inherit lib; };
      schemaLib = import ../nix/lib {
        inherit lib;
        inputs = {
          gen-algebra = inputs.gen-algebra { inherit lib; };
        };
      };
    in
    gen.lib.mkCi {
      inherit inputs;
      name = "gen-schema";
      testModules = ./tests;
      specialArgs = { inherit schemaLib genLib; };
    };
}
