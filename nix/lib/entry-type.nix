{
  lib,
  mkStrictModule,
  identityModule,
  mkMethodsModule,
}:
let
  mkSchemaEntryType =
    {
      strict ? true,
      baseModule ? null,
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

          # Collect methods sidecar from all defs
          allMethods = lib.foldl' (
            acc: d: if builtins.isAttrs d.value && d.value ? methods then acc // d.value.methods else acc
          ) { } defs;

          # Strip methods sidecar before merging (only attrset defs can have methods)
          strippedDefs = map (
            d:
            if builtins.isAttrs d.value && d.value ? methods then
              d // { value = builtins.removeAttrs d.value [ "methods" ]; }
            else
              d
          ) defs;

          # Injected modules
          injected =
            lib.optional (baseModule != null) {
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
                      { ... }:
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
            ]
            ++ lib.optional (allMethods != { }) {
              file = "den-schema/methods";
              value = mkMethodsModule kind allMethods;
            };

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
      baseModule ? null,
    }:
    lib.mkOption {
      description = "Schema — typed record registry with extension points";
      default = { };
      type = lib.types.submodule (
        { config, ... }:
        {
          freeformType = lib.types.lazyAttrsOf (mkSchemaEntryType {
            inherit strict baseModule;
          });
          options._meta = lib.mkOption {
            readOnly = true;
            internal = true;
            type = lib.types.submodule {
              options.kindNames = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                description = "All kind names in the schema";
              };
              options.kindMeta = lib.mkOption {
                type = lib.types.functionTo lib.types.raw;
                description = "Per-kind introspection: options, types, identity keys";
              };
            };
          };
          config._meta = {
            kindNames = lib.sort (a: b: a < b) (
              lib.filter (n: !(lib.hasPrefix "_" n)) (lib.attrNames config)
            );
            kindMeta =
              k:
              let
                dummy = lib.evalModules { modules = [ config.${k} ]; };
              in
              {
                optionNames = lib.attrNames dummy.options;
                options = dummy.options;
                hasIdentity = dummy.options ? id_hash;
                identityKeys = dummy.config._identity.keys or [ ];
              };
          };
        }
      );
    };
in
{
  inherit mkSchemaEntryType mkSchema;
}
