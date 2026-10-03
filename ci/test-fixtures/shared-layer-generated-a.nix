# One of two DISTINCT path modules naming the same `_file`, with a GENERATED value (no source
# position), so the content witness tells them apart by nothing but their file.
{ parent, intOpt, ... }:
{
  _file = "shared-layer:generated";
  config.schema = builtins.listToAttrs [
    {
      name = "base";
      value = builtins.mapAttrs (_: v: v) {
        inherits = [ parent ];
        options.x = intOpt;
      };
    }
  ];
}
