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
  prelude,
  merge,
  identity,
  mkMethodsModule,
  refsFromOptionsWithTypes,
  record,
  applyMixin,
  emitModule,
  isOptionDecl,
  getRefinements,
}:
let
  # ★ THE PROVENANCE MARK (ADR-0034), minted at the ONE site every kind value reaches — both
  # declaration shapes arrive at `mkSchemaEntryType`'s merge, `mkSchemaOption` directly and
  # gen-aspects through `genSchema.mkSchemaOption`. It is what makes "this value came out of a
  # schema" a CHECKABLE property instead of a shape heuristic: the `? kind && ? options` guard it
  # replaces admitted any hand-written attrset, so every message naming a kind value named a
  # provenance its own predicate never looked at.
  #
  # MINTED over the kind's declared INERT surface — its name, the NAME SETS of its options, refs,
  # refinements and collections, its `strict` flag and its `keySemantics` key set. The option
  # `type` checkers and merges, `methods`, `validators`, `mixins`, `computed`, `mkType` and
  # `__functor` are lambdas: the mint refuses them at any depth and there is no substitute
  # (ADR-0034's REFUSED regime). So the mark is an identity over the kind's DECLARED SURFACE and
  # not over its behaviour, and ADR-0013's argued impossibility is written here at the
  # declaration — a lambda's body and captured environment are exposed by no builtin. Two kinds
  # sharing a name and a surface but differing in an option's checker share a mark; within one
  # schema they cannot, because the kind name is in the preimage and names are unique in a schema.
  #
  # NO SECOND MINTING AUTHORITY (ADR-0016 ruling 5). This CONSTRUCTS with the injected mint inside
  # gen-schema's own evaluation, which is ADR-0014's constructing arm; nothing here re-derives an
  # encoder and nothing re-exports `hashIdentity` under gen-schema's name (see ./default.nix).
  #
  # LAZY, and that is load-bearing rather than tidy. The stamp is a thunk: nothing forces it at
  # kind-record construction, so the preimage may reach `introspect.options` — a full
  # `evalModuleTree` of the merged kind module — and is forced only where an identity is DEMANDED,
  # the same stratum `id_hash` and `identityKeys` are already forced at. `isSchemaKind` below is
  # what keeps it that way on the reading side.
  #
  # Hoisted beside `mkAllCollections` for the reason that one is: the label list is ONE derivation
  # read by both arms of the merge, not two spellings of one preimage. `attrNames` is already
  # sorted, so no sort is added.
  markOf =
    components:
    identity.hashIdentity "schemakind" [
      "collections"
      "keySemantics"
      "kind"
      "options"
      "refinements"
      "refs"
      "strict"
    ] (l: components.${l});

  # THE READER of the mark, and the seam's whole admission test. FOUR READS, NONE OF WHICH FORCES
  # THE DIGEST: `v ? __mint` forces `v` to WHNF, and `v.__mint ? minted` forces the mark RECORD and
  # never `minted` itself. That is what lets a guard placed at option-DECLARATION time keep its
  # staging — `mkInstanceRegistry`'s deferred guard reads this on `config.schema.host` while the
  # schema's own options are still being declared, and forcing the digest there would run
  # `introspect`'s `evalModuleTree` on a value that is not yet a value.
  #
  # `? minted` RATHER THAN `? __mint` ALONE, and it is regime selection rather than a defensive
  # extra conjunct: `__mint` is a TAGGED SUM (authored in `gen-algebra/lib/intensional.nix`, whose
  # comment forbids branching on field presence and reading `.minted` raw), so a value carrying no
  # mintable identity has `__mint` present and `minted` absent, and that read aborts uncatchably.
  isSchemaKind = v: builtins.isAttrs v && v ? kind && v ? __mint && v.__mint ? minted;

  # methods is a built-in collection — user collections are additional.
  #
  # Hoisted out of mkSchemaEntryType so the entry type and mkSchemaOption's published
  # `_collectionKeys` share ONE derivation rather than two spellings of one contract.
  # The two reserved-key refusals stay INSIDE this body deliberately: a read of the
  # published key set must reach the same refusal a kind merge does, so a schema that
  # declares a reserved collection is refused whether or not it declares a kind.
  mkAllCollections =
    collections:
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
        # Inheritance, carried as a NAME. It is a BUILT-IN and not a caller-supplied collection
        # because every schema constructor in the ecosystem would otherwise have to re-declare the
        # relation — gen-aspects builds its own option through `mkSchemaOption { collections = …; }`
        # and the acceptance corpus drives its registries through that option. One declaration, one
        # authority. `inherits` is NOT `parent`: parent is containment and feeds
        # `_topology`/`_roots`/`_leaves`, inheritance is composition, and a kind may be nested under
        # one container while inheriting from another.
        inherits = {
          default = [ ];
        };
      }
      // collections;
    in
    if merged ? __functor then
      throw "gen-schema: collection '__functor' is reserved — cannot be used as a collection key"
    else if merged ? kind then
      throw "gen-schema: collection 'kind' is reserved — cannot be used as a collection key"
    # The mark is applied LAST, so without this refusal a collection named `__mint` would be
    # SILENTLY OVERWRITTEN — something vanishes and nothing says so. Same strength and same shape
    # as its two siblings, for the same reason.
    else if merged ? __mint then
      throw "gen-schema: collection '__mint' is reserved — cannot be used as a collection key"
    else
      merged;

  mkSchemaEntryType =
    {
      baseModule ? null,
      collections ? { },
      computed ? null,
      mixins ? [ ],
      mkType ? null,
      strict ? true,
      keySemantics ? { },
    }:
    let
      base = merge.types.deferredModule;

      allCollections = mkAllCollections collections;

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

      collectionKeys = prelude.attrNames allCollections;
    in
    # Built THROUGH mkOptionType rather than as `base // { merge = …; }`. An override over an
    # already completed type answers the protocol as its LEFT operand, so the entry type would
    # carry deferredModule's name, its description and — the one that bites — its functor, whose
    # `type` points back at the plain deferredModule. A typeMerge over two declarations of the
    # same schema option then rebuilds a bare deferredModule and the collection-extracting merge
    # below is gone, silently, with the defs falling through to a plain module import. The entry
    # type is not a deferredModule; it DELEGATES to one (`base.merge`, called inside), and that
    # delegation is the only thing it takes from it.
    merge.mkOptionType {
      name = "schemaKindEntry";
      description = "schema kind entry — options, config, collections and computed fields";
      # deferredModule accepts any def value and lets the merge decide; so does this.
      inherit (base) check;
      merge =
        loc: defs:
        let
          kind = prelude.last loc;

          # Extract each collection from defs, merge with strategy.
          # NOTE: collections must be declared via inline attrsets, not path modules.
          # Path-based kind declarations pass through as paths — the isAttrs check
          # skips them. If two modules declare the same collection key, they merge
          # according to the collection's merge strategy.
          extractedCollections = prelude.mapAttrs (
            name: collection:
            let
              merge = inferMerge name collection;
            in
            prelude.foldl' (
              acc: d: if builtins.isAttrs d.value && d.value ? ${name} then merge acc d.value.${name} else acc
            ) collection.default defs
          ) allCollections;

          # Computed fields from extracted collections + raw defs
          # kind (prelude.last loc) is passed so computed can produce entry-specific fields
          computedFields =
            let
              fields = if computed != null then computed extractedCollections defs else { };
            in
            # `__mint` is refused here for the reason `mkAllCollections` refuses it as a collection
            # key: the stamp is applied last and would overwrite a computed field of that name
            # without saying so.
            if fields ? __mint then
              throw "gen-schema: computed field '__mint' is reserved — the provenance mark is minted by mkSchemaEntryType"
            else
              fields;

          # Strip all collection keys before deferredModule merge
          strippedDefs = map (
            d:
            if builtins.isAttrs d.value && prelude.any (k: d.value ? ${k}) collectionKeys then
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
        in
        if mkType != null then
          # Custom entry type: collection extraction runs first (above),
          # then mkType controls the result. Mixin pipeline, __functor
          # wrapping, and extractedRefinements are all skipped.
          # Precedence: computedFields wins over mkType result for same-named keys,
          # so computed topology/meta fields remain authoritative.
          # strippedDefs are passed so mkType implementations can wire user-declared
          # options/config from the schema kind entry into their own type systems.
          mkType {
            kindModule = resolvedBase;
            collections = extractedCollections;
            defs = strippedDefs;
            inherit kind;
          }
          // {
            inherit strict keySemantics;
            options = { };
            refs = { };
            refinements = { };
          }
          // computedFields
          // {
            # `kind` is the LET-BOUND `prelude.last loc` — the option path, which is
            # authoritative — never the `mkType` result's echo of it, which is caller data.
            # This arm declares no options, refs or refinements (the three literals above), so
            # those components of the preimage are empty by construction, not by omission.
            __mint = {
              minted = markOf {
                inherit kind strict;
                options = [ ];
                refs = [ ];
                refinements = [ ];
                collections = prelude.attrNames extractedCollections;
                keySemantics = prelude.attrNames keySemantics;
              };
            };
          }
        else
          let
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
                        opts = d.value.options or (prelude.filterAttrs (_: isOptionDecl) d.value);
                      in
                      acc // (prelude.filterAttrs (_: v: isOptionDecl v && v ? type && v.type ? __schema) opts)
                    else
                      acc
                  ) { } defs;
                in
                prelude.filterAttrs (_: v: v != [ ]) (
                  prelude.mapAttrs (_: v: getRefinements v.type) allOptionDecls
                );

            # Merge bridge-extracted collections into the collection results
            bridgeCollections =
              if mixinResult != null then
                prelude.mapAttrs (
                  name: stacks:
                  let
                    merge = inferMerge name allCollections.${name};
                  in
                  builtins.foldl' merge (extractedCollections.${name} or allCollections.${name}.default) stacks
                ) (prelude.filterAttrs (n: _: allCollections ? ${n}) mixinResult.collections)
              else
                { };

            finalCollections = extractedCollections // bridgeCollections;

            # Inject baseModule + methods module (methods is the only collection
            # that generates instance-level options via mkMethodsModule)
            injected =
              prelude.optional (effectiveBase != null) {
                file = "gen-schema/base";
                value = effectiveBase;
              }
              ++ prelude.optional (finalCollections.methods != { }) {
                file = "gen-schema/methods";
                value = mkMethodsModule kind finalCollections.methods;
              };

            merged = base.merge loc (strippedDefs ++ injected);

            # Lazy introspection — evaluated on first access of .options or .refs.
            # Uses the locally-built merged module, not config.${k}, to avoid circularity.
            introspect =
              let
                dummy = merge.evalModuleTree { modules = [ merged ]; };
                userOptions = prelude.filterAttrs (n: _: !(prelude.hasPrefix "_module" n)) dummy.options;
              in
              {
                options = userOptions;
                refs = refsFromOptionsWithTypes userOptions;
              };
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
            inherit
              kind
              mixins
              strict
              keySemantics
              ;
            inherit (introspect) options refs;
            refinements = extractedRefinements;
          }
          // finalCollections
          // computedFields
          // {
            # Applied LAST so the mark cannot be shadowed by a collection or a computed field;
            # both are refused by name above rather than left to win silently here.
            __mint = {
              minted = markOf {
                inherit kind strict;
                options = prelude.attrNames introspect.options;
                refs = prelude.attrNames introspect.refs;
                refinements = prelude.attrNames extractedRefinements;
                collections = prelude.attrNames finalCollections;
                keySemantics = prelude.attrNames keySemantics;
              };
            };
          };
    };

  mkSchemaOption =
    {
      strict ? true,
      baseModule ? null,
      collections ? { },
      computed ? null,
      mixins ? [ ],
      mkType ? null,
      keySemantics ? { },
    }:
    merge.mkOption {
      description = "Schema — typed record registry with extension points";
      default = { };
      type = merge.types.submodule (
        { config, options, ... }:
        {
          freeformType = merge.types.lazyAttrsOf (mkSchemaEntryType {
            inherit
              baseModule
              computed
              mixins
              collections
              mkType
              strict
              keySemantics
              ;
          });

          options._kindNames = merge.mkOption {
            type = merge.types.listOf merge.types.str;
            internal = true;
            readOnly = true;
            description = "All kind names in the schema";
          };
          options._topology = merge.mkOption {
            type = merge.types.raw;
            internal = true;
            readOnly = true;
            description = "Parent-child nesting: { kind = { parent, children }; }";
          };
          options._refEdges = merge.mkOption {
            type = merge.types.listOf merge.types.raw;
            internal = true;
            readOnly = true;
            description = "All ref edges: [ { from, field, to } ]";
          };
          options._edges = merge.mkOption {
            type = merge.types.listOf merge.types.raw;
            internal = true;
            readOnly = true;
            description = "Unified edge view: parent (§ Neron 2015 P) + inherits + ref (§ Neron 2015 I) edges";
          };
          options._roots = merge.mkOption {
            type = merge.types.listOf merge.types.str;
            internal = true;
            readOnly = true;
            description = "Kinds with no parent in the topology";
          };
          options._leaves = merge.mkOption {
            type = merge.types.listOf merge.types.str;
            internal = true;
            readOnly = true;
            description = "Kinds with no children in the topology";
          };
          options._collectionKeys = merge.mkOption {
            type = merge.types.listOf merge.types.str;
            internal = true;
            readOnly = true;
            description = "Collection keys extracted from kind defs: built-ins plus this schema's declared collections; a computed field of the same name wins on the kind result, so reading a key through it may return the computed value";
          };
          config =
            let
              # A kind name is any config key that is not one of this submodule's own
              # declared introspection options (_kindNames, _topology, etc. above) — those
              # carry `internal = true`, the same shared per-option marker id-hash.nix's
              # isPrimitiveOption and docs.nix read to separate internal fields from user
              # ones, reused here at the kind-name granularity instead of a re-derived name
              # prefix. A freeform kind has no declared option, so `options.${n}` is absent
              # and the check falls through to `false` — never internal by construction.
              isInternalField = n: options.${n}.internal or false;

              # Reserving the `_` prefix (README: "kind names starting with `_` are
              # reserved for internal use") must be enforced, not merely documented — a
              # reserved name that silently vanished from _kindNames/_topology instead of
              # being refused is exactly the absence-collapse this schema's own reserved
              # collection keys (__functor, kind — above) already refuse loudly.
              reservedKindNames = builtins.filter (n: !(isInternalField n) && prelude.hasPrefix "_" n) (
                prelude.attrNames config
              );

              kindNames =
                if reservedKindNames != [ ] then
                  throw "gen-schema: kind name '${builtins.head reservedKindNames}' is reserved — names starting with '_' are internal use only (_kindNames, _topology, etc.)"
                else
                  prelude.sort (a: b: a < b) (prelude.filter (n: !(isInternalField n)) (prelude.attrNames config));

              # Derive topology from parent collections on each kind.
              # Each kind can declare `parent = "host";` as a collection.
              topology =
                let
                  # Read parent collection from each kind
                  parentMap = prelude.foldl' (
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
                  childrenMap = prelude.foldl' (
                    acc: k:
                    let
                      p = parentMap.${k} or null;
                    in
                    if p != null then acc // { ${p} = (acc.${p} or [ ]) ++ [ k ]; } else acc
                  ) { } kindNames;
                in
                prelude.genAttrs kindNames (k: {
                  parent = parentMap.${k} or null;
                  children = childrenMap.${k} or [ ];
                });

              # Materialize all ref edges from kind.refs across all kinds
              refEdges = prelude.concatMap (
                fromKind:
                let
                  refs = config.${fromKind}.refs;
                in
                prelude.mapAttrsToList (field: refEntry: {
                  from = fromKind;
                  inherit field;
                  to = refEntry.refKind;
                }) refs
              ) kindNames;
              # Unified edge view: § Neron 2015 P (parent) + I (ref/import) edges
              parentEdges = prelude.concatMap (
                k:
                let
                  t = topology.${k};
                in
                prelude.optional (t.parent != null) {
                  from = k;
                  to = t.parent;
                  type = "parent";
                  field = null;
                }
              ) kindNames;

              # The third constituent, derived from the same name graph `evalSchema` stages over —
              # one derivation, not a second spelling. `or [ ]` for a custom `mkType` entry, which
              # carries no collections, exactly as the topology derivation does on `parent`.
              inheritsEdges = prelude.concatMap (
                k:
                map (p: {
                  from = k;
                  to = p;
                  type = "inherits";
                  field = null;
                }) (config.${k}.inherits or [ ])
              ) kindNames;

              edges = parentEdges ++ inheritsEdges ++ map (e: e // { type = "ref"; }) refEdges;

              roots = builtins.filter (k: topology.${k}.parent == null) kindNames;
              leaves = builtins.filter (k: topology.${k}.children == [ ]) kindNames;

            in
            {
              _kindNames = kindNames;
              _topology = topology;
              _refEdges = refEdges;
              _edges = edges;
              _roots = roots;
              _leaves = leaves;
              # The same derivation the entry type extracts with — not a second spelling.
              # attrNames is already sorted, so no sort is added.
              _collectionKeys = prelude.attrNames (mkAllCollections collections);
            };
        }
      );
    };
in
{
  inherit mkSchemaEntryType mkSchemaOption isSchemaKind;
}
