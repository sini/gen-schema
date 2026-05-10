{
  lib,
  mkStrictModule,
  identityModule,
}:
let
  mkSchemaEntryType =
    {
      strict ? true,
      baseModule ? { },
    }:
    let
      base = lib.types.deferredModule;
    in
    base
    // {
      merge =
        loc: defs:
        let
          kind = lib.last loc;

          # Strip methods sidecar (future Task 8)
          strippedDefs = map (
            d:
            if builtins.isAttrs d.value then d // { value = builtins.removeAttrs d.value [ "methods" ]; } else d
          ) defs;

          # Injected modules
          injected =
            lib.optional (baseModule != { }) {
              file = "den-schema/base";
              value = baseModule;
            }
            ++ [
              (
                if strict then
                  {
                    file = "den-schema/strict-default";
                    value = mkStrictModule kind;
                  }
                else
                  {
                    file = "den-schema/permissive";
                    value =
                      { lib, ... }:
                      {
                        _module.freeformType = lib.types.attrsOf lib.types.anything;
                      };
                  }
              )
            ]
            ++ [
              {
                file = "den-schema/identity";
                value = identityModule kind;
              }
            ];

          merged = base.merge loc (strippedDefs ++ injected);
        in
        {
          __functor =
            _:
            { ... }:
            {
              imports = [ merged ];
            };
        };
    };

  mkSchema =
    {
      strict ? true,
      baseModule ? { },
    }:
    lib.mkOption {
      description = "Schema — typed record registry with extension points";
      default = { };
      type = lib.types.submodule {
        freeformType = lib.types.lazyAttrsOf (mkSchemaEntryType {
          inherit strict baseModule;
        });
      };
    };
in
{
  inherit mkSchemaEntryType mkSchema;
}
