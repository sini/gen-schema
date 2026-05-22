{
  description = "gen-schema: typed record registry with extension points for Nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { nixpkgs, ... }:
    let
      schemaLib = import ./nix/lib {
        lib = nixpkgs.lib;
      };
    in
    {
      lib = schemaLib;
      flakeModules.default = ./nix/flakeModule.nix;
    };
}
