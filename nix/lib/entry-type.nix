# Schema entry type and mkSchemaOption.
#
# A schema kind is a pure declaration — options, config, defaults, methods,
# and user-defined collection fields. Collections are extracted from defs before
# deferred module merge and exposed as attributes on the merged result.
# Computed fields are derived from extracted collections post-merge.
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
  isOptionDecl,
  isRefined,
  getRefinements,
}:
let
  mkSchemaEntryType =
    {
      baseModule ? null,
      collections ? { },
      computed ? null,
      mixins ? [ ],
    }:
    let
      base = lib.types.deferredModule;

      # methods is a built-in collection — user collections are additional
      allCollections =
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
          // collections;
        in
        if merged ? __functor then
          throw "gen-schema: collection '__functor' is reserved — cannot be used as a collection key"
        else if merged ? kind then
          throw "gen-schema: collection 'kind' is reserved — cannot be used as a collection key"
        else
          merged;

      # Infer merge strategy from default type
      inferMerge =
        name: collection:
        if collection ? merge then
          collection.merge
        else if builtins.isList collection.default then
          (acc: val: acc ++ val)
        else if builtins.isAttrs collection.default then
          (acc: val: acc // val)
        else
          throw "gen-schema: collection '${name}': no merge strategy — default is not a list or attrset; provide an explicit merge function";

      collectionKeys = lib.attrNames allCollections;
    in
    base
    // {
      merge =
        loc: defs:
        let
          kind = lib.last loc;

          # Extract each collection from defs, merge with strategy.
          # NOTE: collections must be declared via inline attrsets, not path modules.
          # Path-based kind declarations pass through as paths — the isAttrs check
          # skips them. If two modules declare the same collection key, they merge
          # according to the collection's merge strategy.
          extractedCollections = lib.mapAttrs (
            name: collection:
            let
              merge = inferMerge name collection;
            in
            lib.foldl' (
              acc: d: if builtins.isAttrs d.value && d.value ? ${name} then merge acc d.value.${name} else acc
            ) collection.default defs
          ) allCollections;

          # Computed fields from extracted collections + raw defs
          # kind (lib.last loc) is passed so computed can produce entry-specific fields
          computedFields = if computed != null then computed extractedCollections defs else { };

          # Strip all collection keys before deferredModule merge
          strippedDefs = map (
            d:
            if builtins.isAttrs d.value && lib.any (k: d.value ? ${k}) collectionKeys then
              d // { value = builtins.removeAttrs d.value collectionKeys; }
            else
              d
          ) defs;

          # Resolve baseModule value (may be a function of kind name)
          resolvedBase =
            if baseModule == null then
              null
            else if builtins.isFunction baseModule then
              baseModule kind
            else
              baseModule;

          # When mixins are present and baseModule is an inline attrset,
          # apply mixins via the record algebra and emit through the bridge.
          hasMixins = mixins != [ ] && resolvedBase != null && builtins.isAttrs resolvedBase;

          mixinResult =
            if hasMixins then
              let
                baseRecord = record.fromAttrs resolvedBase;
                withMixins = builtins.foldl' (acc: m: applyMixin m acc kind) baseRecord mixins;
                emitted = emitModule collectionKeys withMixins;
              in
              emitted
            else
              null;

          # Effective base module: bridge output when mixins applied, original otherwise
          effectiveBase = if mixinResult != null then mixinResult.module else resolvedBase;

          # Refinements extracted from option declarations.
          # Mixin path: bridge already extracted them.
          # Non-mixin path: scan all defs for mkOption values with __schema metadata.
          # Stored on the kind result so mkInstanceRegistry can consume them automatically.
          extractedRefinements =
            if mixinResult != null then
              mixinResult.refinements
            else
              let
                # Collect option declarations from all defs (inline attrsets only).
                # Tries d.value.options first (module-style { options.x = mkOption ...; })
                # then falls back to scanning d.value for mkOption values directly
                # (flat-style { x = mkOption ...; }). Assumes a user field named "options"
                # won't contain mkOption values — this is safe because mkOption produces
                # attrsets with _type = "option" which user data never has.
                allOptionDecls = builtins.foldl' (
                  acc: d:
                  if builtins.isAttrs d.value then
                    let
                      opts = d.value.options or (lib.filterAttrs (_: isOptionDecl) d.value);
                    in
                    acc // (lib.filterAttrs (_: v: isOptionDecl v && v ? type && v.type ? __schema) opts)
                  else
                    acc
                ) { } defs;
              in
              lib.filterAttrs (_: v: v != [ ]) (lib.mapAttrs (_: v: getRefinements v.type) allOptionDecls);

          # Merge bridge-extracted collections into the collection results
          bridgeCollections =
            if mixinResult != null then
              lib.mapAttrs (
                name: stacks:
                let
                  merge = inferMerge name allCollections.${name};
                in
                builtins.foldl' merge (extractedCollections.${name} or allCollections.${name}.default) stacks
              ) (lib.filterAttrs (n: _: allCollections ? ${n}) mixinResult.collections)
            else
              { };

          finalCollections = extractedCollections // bridgeCollections;

          # Inject baseModule + methods module (methods is the only collection
          # that generates instance-level options via mkMethodsModule)
          injected =
            lib.optional (effectiveBase != null) {
              file = "gen-schema/base";
              value = effectiveBase;
            }
            ++ lib.optional (finalCollections.methods != { }) {
              file = "gen-schema/methods";
              value = mkMethodsModule kind finalCollections.methods;
            };

          merged = base.merge loc (strippedDefs ++ injected);
        in
        # Precedence: computed overrides collections of the same name.
        # __functor is reserved — collections/computed must not use it as a key.
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
        // finalCollections
        // computedFields;
    };

  mkSchemaOption =
    {
      strict ? true,
      baseModule ? null,
      collections ? { },
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
              computed
              mixins
              collections
              ;
          });

          # Schema-level strict setting — stored for mkInstanceType to read
          options._strict = lib.mkOption {
            internal = true;
            type = lib.types.bool;
            default = strict;
          };

          options._kindNames = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            internal = true;
            readOnly = true;
            description = "All kind names in the schema";
          };
          options._kindMeta = lib.mkOption {
            type = lib.types.functionTo lib.types.raw;
            internal = true;
            readOnly = true;
            description = "Per-kind introspection: options, types, identity keys, refs";
          };
          options._topology = lib.mkOption {
            type = lib.types.raw;
            internal = true;
            readOnly = true;
            description = "Parent-child nesting: { kind = { parent, children }; }";
          };
          options._refEdges = lib.mkOption {
            type = lib.types.listOf lib.types.raw;
            internal = true;
            readOnly = true;
            description = "All ref edges: [ { from, field, to } ]";
          };
          options._edges = lib.mkOption {
            type = lib.types.listOf lib.types.raw;
            internal = true;
            readOnly = true;
            description = "Unified edge view: parent (Neron P) + ref (Neron I) edges";
          };
          options._roots = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            internal = true;
            readOnly = true;
            description = "Kinds with no parent in the topology";
          };
          options._leaves = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            internal = true;
            readOnly = true;
            description = "Kinds with no children in the topology";
          };
          config =
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

              # Derive topology from parent collections on each kind.
              # Each kind can declare `parent = "host";` as a collection.
              topology =
                let
                  # Read parent collection from each kind
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
              _kindNames = kindNames;
              _kindMeta = kindMeta;
              _topology = topology;
              _refEdges = refEdges;
              _edges = edges;
              _roots = roots;
              _leaves = leaves;
            };
        }
      );
    };
in
{
  inherit mkSchemaEntryType mkSchemaOption;
}
