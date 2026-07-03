# The schema OPTION declaration — the typed registry surface, declared PURELY inside the gen tree.
#
# This is the `options.schema = mkSchemaOption {}` the old flake-parts `modules/schema.nix` embedded
# (via `gen-schema.flakeModules.default`). Relocating it here is the crux of the migration: gen-merge's
# `evalModuleTree` — gen-schema's own host engine — handles the gen schema TYPE natively, whereas
# flake-parts' nixpkgs `lib.evalModules` walked it via `substSubModules`/`getSubOptions` and threw.
# The kind bodies (`config.schema.<kind>`) live in ./schema/*.nix; the instance registries
# (`options.fleet.<kind>`) in ./fleet/registries.nix. The resolved values cross to the flake-parts
# reader via gen-flake's injected `genValues`; the gen type never leaves this pure eval.
{ genSchema, ... }:
{
  options.schema = genSchema.mkSchemaOption { };
}
