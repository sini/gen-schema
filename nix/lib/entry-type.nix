# Schema entry type and mkSchemaOption.
#
# A schema kind is a pure declaration — options, config, defaults, methods.
# It does NOT include strict validation or identity hashing; those are
# instance-level concerns injected by mkInstanceType. This means kind-level
# composition via `imports = [ config.schema.user ]` works without duplicate
# infrastructure module conflicts.
{
  lib,
  mkMethodsModule,
}:
let
  mkSchemaEntryType =
    {
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

          # Collect methods sidecar from all defs.
          # NOTE: methods must be declared via inline attrsets, not path modules.
          # Path-based kind declarations (e.g., `schema.host = ./host.nix;`) pass
          # through as paths — the isAttrs check skips them, so methods declared
          # in path modules are not extracted and will cause strict mode errors.
          # If two modules declare the same method name, the later def wins (// semantics).
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

          # Injected modules — only baseModule and methods (no strict/identity)
          injected =
            lib.optional (baseModule != null) {
              file = "den-schema/base";
              value = baseModule;
            }
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

  mkSchemaOption =
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
            inherit baseModule;
          });

          # Schema-level strict setting — stored for mkInstanceType to read
          options._strict = lib.mkOption {
            internal = true;
            type = lib.types.bool;
            default = strict;
          };

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
              if !(config ? ${k}) then
                throw "kindMeta: '${k}' is not a declared schema kind"
              else
                let
                  dummy = lib.evalModules { modules = [ config.${k} ]; };
                in
                {
                  optionNames = lib.attrNames dummy.options;
                  options = dummy.options;
                  hasIdentity = false; # bare schema kinds don't have identity
                  identityKeys = [ ];
                };
          };
        }
      );
    };
in
{
  inherit mkSchemaEntryType mkSchemaOption;
}
