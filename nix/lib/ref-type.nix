{ lib }:
{
  mkRefType =
    instances:
    lib.mkOptionType {
      name = "refType";
      description = "reference to an instance key";
      check = builtins.isString;
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
