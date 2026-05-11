{ lib }:
{
  mkStrictModule =
    kind:
    { ... }:
    {
      _module.freeformType = lib.mkDefault (lib.mkOptionType {
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
      });
    };
}
