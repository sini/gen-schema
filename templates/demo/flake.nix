{
  inputs = {
    den-schema.url = "github:denful/den-schema";
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
  };

  outputs = { den-schema, nixpkgs, ... }:
    let
      lib = nixpkgs.lib;
      schemaLib = den-schema.lib;
    in {
      schema = {};
    };
}
