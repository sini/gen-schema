# The shared layer FILE setting its own `_file` per application: a path module is named by it.
{
  parent,
  intOpt,
  tag,
  ...
}:
{
  _file = "shared-layer:${tag}";
  config.schema.base = {
    inherits = [ parent ];
    options.x = intOpt;
  };
}
