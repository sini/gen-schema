# Wiring: import gen-schema's flake-parts module.
# This provides options.schema and _module.args.genSchema.
{ lib, inputs, ... }:
{
  imports = [
    inputs.gen-schema.flakeModules.default
  ];
  config._module.args = {
    genAlgebra = inputs.gen-algebra { inherit lib; };
    inherit inputs;
  };
}
