{
  description = "den-schema: typed record registry with extension points for Nix";

  inputs.nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";

  outputs = { nixpkgs, ... }:
    let
      schemaLib = import ./nix/lib { lib = nixpkgs.lib; };
    in {
      lib = schemaLib;
      flakeModules.default = ./nix/flakeModule.nix;
    };
}
