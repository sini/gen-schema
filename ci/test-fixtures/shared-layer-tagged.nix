# The shared layer FILE setting its own `_file` per application: a path module takes its file from the path.
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
