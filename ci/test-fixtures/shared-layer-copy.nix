# A second copy of `shared-layer.nix` at a distinct path, which is a distinct source.
{ parent, intOpt, ... }:
{
  config.schema.base = {
    inherits = [ parent ];
    options.x = intOpt;
  };
}
