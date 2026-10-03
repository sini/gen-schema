# One layer module FILE, applied in several trees by path (den-hoag-4i0o5, `witness-collision-refusals`).
{ parent, intOpt, ... }:
{
  config.schema.base = {
    inherits = [ parent ];
    options.x = intOpt;
  };
}
