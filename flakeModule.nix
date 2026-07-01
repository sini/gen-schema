# flake-parts module for gen-schema.
#
# Provides:
#   options.schema — typed record registry (mkSchemaOption {})
#   config._module.args.genSchema — library functions for use in modules
#
# For customization of strict/baseModule, use the programmatic API
# (gen-schema.lib.mkSchemaOption { ... }) instead of this module.
{ lib, ... }:
let
  # Dual-source (sound, content-addressed): option types use the *consumer's*
  # lib, but `algebra` is pinned from this repo's own flake.lock so the module
  # value stays in lockstep with `.lib`'s API (per the gen root-file convention).
  lock = builtins.fromJSON (builtins.readFile ./flake.lock);
  algebra = import "${builtins.fetchTree lock.nodes.gen-algebra.locked}/lib";
  genSchema = import ./lib { inherit lib algebra; };
in
{
  options.schema = genSchema.mkSchemaOption { };
  config._module.args.genSchema = genSchema;
}
