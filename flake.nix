{
  description = "gen-schema: typed record registry with extension points for Nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    gen.url = "github:sini/gen";
  };

  outputs = { nixpkgs, gen, ... }:
    let
      schemaLib = import ./nix/lib {
        lib = nixpkgs.lib;
        inputs = { gen = import "${gen}" { lib = nixpkgs.lib; }; };
      };
    in {
      lib = schemaLib;
      flakeModules.default = ./nix/flakeModule.nix;
    };
}
