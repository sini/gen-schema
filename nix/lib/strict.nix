# mkStrictModule — closed-world instance schemas.
#
# Sets a kind's `_module.freeformType` to a type whose merge always throws, so
# any key not declared as an option is rejected with a fix suggestion. This turns
# the module system's open (freeform) default into a closed record for instances
# that opt into `strict` (see instance.nix).
#
# Relocated from gen-algebra/module so gen-schema owns its full module-system
# surface; gen-algebra is the pure algebra root.
{ lib }:
{
  mkStrictModule =
    kind:
    { ... }:
    {
      _module.freeformType = lib.mkDefault (
        lib.mkOptionType {
          name = "strict";
          merge =
            path: _decls:
            let
              key = lib.last path;
            in
            throw ''
              STRICT MODE: "${key}" is not declared on ${kind}.
              Fix: schema.${kind}.options.${key} = lib.mkOption { ... };
            '';
        }
      );
    };
}
