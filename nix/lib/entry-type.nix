# Schema entry type and mkSchemaOption.
#
# A schema kind is a pure declaration — options, config, defaults, methods,
# and user-defined sidecar fields. Sidecars are extracted from defs before
# deferred module merge and exposed as attributes on the merged result.
# Computed fields are derived from extracted sidecars post-merge.
#
# Strict validation and identity hashing are instance-level concerns
# injected by mkInstanceType, not here.
{
  lib,
  mkMethodsModule,
}:
let
  mkSchemaEntryType =
    {
      baseModule ? null,
      sidecars ? { },
      computed ? null,
    }:
    let
      base = lib.types.deferredModule;

      # methods is a built-in sidecar — user sidecars are additional
      allSidecars =
        let
          merged = {
            methods = {
              default = { };
            };
            validators = {
              default = [ ];
            };
          }
          // sidecars;
        in
        if merged ? __functor then
          throw "sidecar '__functor' is reserved — cannot be used as a sidecar key"
        else
          merged;

      # Infer merge strategy from default type
      inferMerge =
        name: sidecar:
        if sidecar ? merge then
          sidecar.merge
        else if builtins.isList sidecar.default then
          (acc: val: acc ++ val)
        else if builtins.isAttrs sidecar.default then
          (acc: val: acc // val)
        else
          throw "sidecar '${name}': no merge strategy — default is not a list or attrset; provide an explicit merge function";

      sidecarKeys = lib.attrNames allSidecars;
    in
    base
    // {
      merge =
        loc: defs:
        let
          kind = lib.last loc;

          # Extract each sidecar from defs, merge with strategy.
          # NOTE: sidecars must be declared via inline attrsets, not path modules.
          # Path-based kind declarations pass through as paths — the isAttrs check
          # skips them. If two modules declare the same sidecar key, they merge
          # according to the sidecar's merge strategy.
          extractedSidecars = lib.mapAttrs (
            name: sidecar:
            let
              merge = inferMerge name sidecar;
            in
            lib.foldl' (
              acc: d: if builtins.isAttrs d.value && d.value ? ${name} then merge acc d.value.${name} else acc
            ) sidecar.default defs
          ) allSidecars;

          # Computed fields from extracted sidecars + raw defs
          computedFields = if computed != null then computed extractedSidecars defs else { };

          # Strip all sidecar keys before deferredModule merge
          strippedDefs = map (
            d:
            if builtins.isAttrs d.value && lib.any (k: d.value ? ${k}) sidecarKeys then
              d // { value = builtins.removeAttrs d.value sidecarKeys; }
            else
              d
          ) defs;

          # Inject baseModule + methods module (methods is the only sidecar
          # that generates instance-level options via mkMethodsModule)
          injected =
            lib.optional (baseModule != null) {
              file = "den-schema/base";
              value = baseModule;
            }
            ++ lib.optional (extractedSidecars.methods != { }) {
              file = "den-schema/methods";
              value = mkMethodsModule kind extractedSidecars.methods;
            };

          merged = base.merge loc (strippedDefs ++ injected);
        in
        # Precedence: computed overrides sidecars of the same name.
        # __functor is reserved — sidecars/computed must not use it as a key.
        {
          __functor =
            _:
            { ... }:
            {
              imports = [ merged ];
            };
          entryName = kind;
        }
        // extractedSidecars
        // computedFields;
    };

  mkSchemaOption =
    {
      strict ? true,
      baseModule ? null,
      sidecars ? { },
      computed ? null,
    }:
    lib.mkOption {
      description = "Schema — typed record registry with extension points";
      default = { };
      type = lib.types.submodule (
        { config, ... }:
        {
          freeformType = lib.types.lazyAttrsOf (mkSchemaEntryType {
            inherit baseModule sidecars computed;
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
            kindNames = lib.sort (a: b: a < b) (lib.filter (n: !(lib.hasPrefix "_" n)) (lib.attrNames config));
            kindMeta =
              k:
              if !(config ? ${k}) then
                throw "kindMeta: '${k}' is not a declared schema kind"
              else
                let
                  dummy = lib.evalModules { modules = [ config.${k} ]; };
                  # Extract refKind from a type, traversing nullOr/listOf wrappers.
                  getRefKind = type:
                    if (type.refKind or null) != null then type.refKind
                    else if (type.nestedTypes.elemType.refKind or null) != null then type.nestedTypes.elemType.refKind
                    else null;
                  refFields = lib.filterAttrs (
                    _: opt: (opt ? type) && (getRefKind opt.type) != null
                  ) dummy.options;
                in
                {
                  optionNames = lib.attrNames dummy.options;
                  options = dummy.options;
                  refs = lib.mapAttrs (_: opt: getRefKind opt.type) refFields;
                };
          };
        }
      );
    };
in
{
  inherit mkSchemaEntryType mkSchemaOption;
}
