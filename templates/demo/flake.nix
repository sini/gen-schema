{
  description = "gen-schema demo: typed fleet management with schema, refs, and strict validation";

  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./modules);

  inputs = {
    gen-schema.url = "github:sini/gen-schema";
    gen-algebra.url = "github:sini/gen-algebra";
    import-tree.url = "github:vic/import-tree";
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };
}
