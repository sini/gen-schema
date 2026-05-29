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
  genSchema = import ./lib { inherit lib; };
in
{
  options.schema = genSchema.mkSchemaOption { };
  config._module.args.genSchema = genSchema;
}
