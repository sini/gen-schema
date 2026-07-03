# flake-parts module for gen-schema.
#
# Provides:
#   options.schema — typed record registry (mkSchemaOption {})
#   config._module.args.genSchema — library functions for use in modules
#
# For customization of strict/baseModule, use the programmatic API
# (gen-schema.lib.mkSchemaOption { ... }) instead of this module.
{ ... }:
let
  # gen-schema now drives on gen-merge's byte-mode engine (NOT nixpkgs lib), so the whole
  # library — including `mkSchemaOption`'s type — is self-pinned from this repo's flake.lock
  # (per the gen root-file convention), no longer parameterised by a consumer `lib`.
  #
  # NB: the resulting `options.schema` type is a gen-merge type. A consumer evaluating this
  # module with nixpkgs `lib.evalModules` cannot drive it (gen-merge types don't implement the
  # nixpkgs type interface). Use gen-merge's `evalModuleTree`, or the programmatic API.
  genSchema = import ./default.nix { };
in
{
  options.schema = genSchema.mkSchemaOption { };
  config._module.args.genSchema = genSchema;
}
