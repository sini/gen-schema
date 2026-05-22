{
  description = "gen-schema: typed record registry with extension points for Nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { nixpkgs, ... }:
    let
      inherit (nixpkgs) lib;
      schemaLib = import ./nix/lib { inherit lib; };
    in
    {
      lib = schemaLib;
      flakeModules.default = ./nix/flakeModule.nix;
    };
}
