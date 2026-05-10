{
  inputs = {
    den-schema.url = "github:denful/den-schema";
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
    nix-unit.url = "github:nix-community/nix-unit";
    nix-unit.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { den-schema, nixpkgs, nix-unit, ... }:
    let
      lib = nixpkgs.lib;
      schemaLib = den-schema.lib;
      forAllSystems = lib.genAttrs lib.systems.flakeExposed;
      testFiles = lib.pipe (builtins.readDir ./tests) [
        (lib.filterAttrs (n: v: v == "regular" && lib.hasSuffix ".nix" n))
        builtins.attrNames
      ];
      tests = lib.foldl' (acc: file:
        acc // (import ./tests/${file} { inherit lib schemaLib; })
      ) {} testFiles;
    in {
      inherit tests;
      devShells = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in {
          default = pkgs.mkShell {
            packages = [ nix-unit.packages.${system}.default ];
          };
        }
      );
    };
}
