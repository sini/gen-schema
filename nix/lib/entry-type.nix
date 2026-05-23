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
  refsFromOptions,
  record,
  applyMixin,
  emitModule,
}:
let
  mkSchemaEntryType =
    {
      baseModule ? null,
      sidecars ? { },
      computed ? null,
      mixins ? [ ],
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
            parent = {
              default = null;
              merge =
                acc: val:
                if acc != null && val != acc then
                  throw "gen-schema: conflicting parent declarations: '${acc}' vs '${val}'"
                else
                  val;
            };
          }
          // sidecars;
        in
        if merged ? __functor then
          throw "gen-schema: sidecar '__functor' is reserved — cannot be used as a sidecar key"
        else if merged ? kind then
          throw "gen-schema: sidecar 'kind' is reserved — cannot be used as a sidecar key"
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
          throw "gen-schema: sidecar '${name}': no merge strategy — default is not a list or attrset; provide an explicit merge function";

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
          # kind (lib.last loc) is passed so computed can produce entry-specific fields
          computedFields = if computed != null then computed extractedSidecars defs else { };

          # Strip all sidecar keys before deferredModule merge
          strippedDefs = map (
            d:
            if builtins.isAttrs d.value && lib.any (k: d.value ? ${k}) sidecarKeys then
              d // { value = builtins.removeAttrs d.value sidecarKeys; }
            else
              d
          ) defs;

          # Resolve baseModule value (may be a function of kind name)
          resolvedBase =
            if baseModule == null then null
            else if builtins.isFunction baseModule then baseModule kind
            else baseModule;

          # When mixins are present and baseModule is an inline attrset,
          # apply mixins via the record algebra and emit through the bridge.
          hasMixins = mixins != [ ] && resolvedBase != null && builtins.isAttrs resolvedBase;

          mixinResult =
            if hasMixins then
              let
                baseRecord = record.fromAttrs resolvedBase;
                withMixins = builtins.foldl' (
                  acc: m: applyMixin m acc kind
                ) baseRecord mixins;
                emitted = emitModule sidecarKeys withMixins;
              in
              emitted
            else
              null;

          # Effective base module: bridge output when mixins applied, original otherwise
          effectiveBase =
            if mixinResult != null then mixinResult.module
            else resolvedBase;

          # Refinements extracted from option declarations.
          # Mixin path: bridge already extracted them.
          # Non-mixin path: scan all defs for mkOption values with __schema metadata.
          # Stored on the kind result so mkInstanceRegistry can consume them automatically.
          extractedRefinements =
            if mixinResult != null then mixinResult.refinements
            else
              let
                inherit (import ./refined.nix { inherit lib; }) isRefined getRefinements;
                isOptionDecl = v: builtins.isAttrs v && v ? _type && v._type == "option";
                # Collect option declarations from all defs (inline attrsets only)
                allOptionDecls = builtins.foldl' (acc: d:
                  if builtins.isAttrs d.value then
                    let
                      # Look for options.* or direct mkOption values
                      opts = d.value.options or (lib.filterAttrs (_: isOptionDecl) d.value);
                    in
                    acc // (lib.filterAttrs (_: v: isOptionDecl v && v ? type && v.type ? __schema) opts)
                  else acc
                ) {} defs;
              in
              lib.filterAttrs (_: v: v != []) (
                lib.mapAttrs (_: v: getRefinements v.type) allOptionDecls
              );

          # Merge bridge-extracted sidecars into the sidecar results
          bridgeSidecars =
            if mixinResult != null then
              lib.mapAttrs (name: stacks:
                let merge = inferMerge name allSidecars.${name};
                in builtins.foldl' merge (extractedSidecars.${name} or allSidecars.${name}.default) stacks
              ) (lib.filterAttrs (n: _: allSidecars ? ${n}) mixinResult.sidecars)
            else
              { };

          finalSidecars = extractedSidecars // bridgeSidecars;

          # Inject baseModule + methods module (methods is the only sidecar
          # that generates instance-level options via mkMethodsModule)
          injected =
            lib.optional (effectiveBase != null) {
              file = "gen-schema/base";
              value = effectiveBase;
            }
            ++ lib.optional (finalSidecars.methods != { }) {
              file = "gen-schema/methods";
              value = mkMethodsModule kind finalSidecars.methods;
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
          inherit kind mixins;
          refinements = extractedRefinements;
        }
        // finalSidecars
        // computedFields;
    };

  mkSchemaOption =
    {
      strict ? true,
      baseModule ? null,
      sidecars ? { },
      computed ? null,
      mixins ? [ ],
    }:
    lib.mkOption {
      description = "Schema — typed record registry with extension points";
      default = { };
      type = lib.types.submodule (
        { config, ... }:
        {
          freeformType = lib.types.lazyAttrsOf (mkSchemaEntryType {
            inherit
              baseModule
              sidecars
              computed
              mixins
              ;
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
                description = "Per-kind introspection: options, types, identity keys, refs";
              };
              options.topology = lib.mkOption {
                type = lib.types.raw;
                description = "Parent-child nesting: { kind = { parent, children }; }";
              };
              options.refEdges = lib.mkOption {
                type = lib.types.listOf lib.types.raw;
                description = "All ref edges: [ { from, field, to } ]";
              };
              options.edges = lib.mkOption {
                type = lib.types.listOf lib.types.raw;
                description = "Unified edge view: parent (Neron P) + ref (Neron I) edges";
              };
              options.roots = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                description = "Kinds with no parent in the topology";
              };
              options.leaves = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                description = "Kinds with no children in the topology";
              };
            };
          };
          config._meta =
            let
              kindNames = lib.sort (a: b: a < b) (lib.filter (n: !(lib.hasPrefix "_" n)) (lib.attrNames config));

              # Memoized as attrset — each kind's evalModules runs at most once.
              kindMeta =
                let
                  memo = lib.genAttrs kindNames (
                    k:
                    let
                      dummy = lib.evalModules { modules = [ config.${k} ]; };
                    in
                    {
                      optionNames = lib.attrNames dummy.options;
                      inherit (dummy) options;
                      refs = refsFromOptions dummy.options;
                    }
                  );
                in
                k:
                if memo ? ${k} then
                  memo.${k}
                else
                  throw "gen-schema: kindMeta: '${k}' is not a declared schema kind";

              # Derive topology from parent sidecars on each kind.
              # Each kind can declare `parent = "host";` as a sidecar.
              topology =
                let
                  # Read parent sidecar from each kind
                  parentMap = lib.foldl' (
                    acc: k:
                    let
                      p = config.${k}.parent or null;
                    in
                    if p != null then
                      if !(builtins.elem p kindNames) then
                        throw "gen-schema: kind '${k}' declares parent '${p}' which is not a declared kind"
                      else
                        acc // { ${k} = p; }
                    else
                      acc
                  ) { } kindNames;

                  # Derive children from parent map (inverse)
                  childrenMap = lib.foldl' (
                    acc: k:
                    let
                      p = parentMap.${k} or null;
                    in
                    if p != null then acc // { ${p} = (acc.${p} or [ ]) ++ [ k ]; } else acc
                  ) { } kindNames;
                in
                lib.genAttrs kindNames (k: {
                  parent = parentMap.${k} or null;
                  children = childrenMap.${k} or [ ];
                });

              # Materialize all ref edges from kindMeta.refs across all kinds
              refEdges = lib.concatMap (
                fromKind:
                let
                  refs = (kindMeta fromKind).refs;
                in
                lib.mapAttrsToList (field: toKind: {
                  from = fromKind;
                  inherit field;
                  to = toKind;
                }) refs
              ) kindNames;
              # Unified edge view: Neron P (parent) + I (ref/import) edges
              parentEdges = lib.concatMap (
                k:
                let
                  t = topology.${k};
                in
                lib.optional (t.parent != null) {
                  from = k;
                  to = t.parent;
                  type = "parent";
                  field = null;
                }
              ) kindNames;

              edges = parentEdges ++ map (e: e // { type = "ref"; }) refEdges;

              roots = builtins.filter (k: topology.${k}.parent == null) kindNames;
              leaves = builtins.filter (k: topology.${k}.children == [ ]) kindNames;
            in
            {
              inherit
                kindNames
                kindMeta
                topology
                refEdges
                edges
                roots
                leaves
                ;
            };
        }
      );
    };
in
{
  inherit mkSchemaEntryType mkSchemaOption;
}
