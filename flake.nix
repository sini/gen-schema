{
  description = "gen-schema: typed record registry with extension points for Nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { nixpkgs, ... }:
    let
<<<<<<< Updated upstream
      schemaLib = import ./nix/lib {
        lib = nixpkgs.lib;
      };
    in
    {
||||||| Stash base
      schemaLib = import ./nix/lib {
        lib = nixpkgs.lib;
      };
    in {
=======
      inherit (nixpkgs) lib;
      schemaLib = import ./nix/lib { inherit lib; };
    in
    {
>>>>>>> Stashed changes
      lib = schemaLib;
      flakeModules.default = ./nix/flakeModule.nix;
    };
}
