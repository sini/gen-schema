# Wiring: import den-schema's flake-parts module.
# This provides options.schema and _module.args.schemaLib.
{ inputs, ... }:
{
  imports = [
    inputs.den-schema.flakeModules.default
  ];
  config._module.args = {
    bend = inputs.bend.lib;
    inherit inputs;
  };
}
