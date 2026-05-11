# flake-parts module for den-schema.
#
# Provides:
#   options.schema — typed record registry (mkSchemaOption {})
#   config._module.args.schemaLib — library functions for use in modules
#
# For customization of strict/baseModule, use the programmatic API
# (den-schema.lib.mkSchemaOption { ... }) instead of this module.
{ lib, ... }:
let
  schemaLib = import ./lib { inherit lib; };
in
{
  options.schema = schemaLib.mkSchemaOption { };
  config._module.args.schemaLib = schemaLib;
}
