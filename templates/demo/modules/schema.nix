# Wiring: import den-schema's flake-parts module.
# This provides options.schema and _module.args.schemaLib.
{ inputs, ... }:
{
  imports = [
    inputs.den-schema.flakeModules.default
  ];
}
