{ lib }:
{
  mkRefType =
    instances:
    lib.types.str
    // {
      name = "refType";
      check = v: builtins.isString v;
      merge =
        loc: defs:
        let
          key = lib.mergeOneOption loc defs;
        in
        if instances ? ${key} then
          instances.${key}
        else
          throw "${lib.showOption loc}: reference '${key}' not found in instance registry";
    };
}
