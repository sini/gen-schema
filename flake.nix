{
  description = "gen-schema: typed record registry with extension points for Nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    gen-algebra.url = "github:sini/gen-algebra";
  };

  outputs =
    { nixpkgs, gen-algebra, ... }:
    {
      lib = import ./lib {
        lib = nixpkgs.lib;
        algebra = gen-algebra.lib;
      };
      flakeModules.default = ./flakeModule.nix;
    };
}
