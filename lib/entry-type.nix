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

  # THE REFINEMENT PLANE IS A PROJECTION OF AN OPTION PLANE (ADR-0013: a derivable fact is derived,
  # once). Every arm that publishes `refinements` from an evaluated option plane reads it through this
  # one binding, so two arms cannot disagree on what a refined option contributes.
  refinementsOfOptions =
    opts:
    prelude.filterAttrs (_: v: v != [ ]) (
      prelude.mapAttrs (_: o: getRefinements o.type) (
        prelude.filterAttrs (_: o: isOptionDecl o && o ? type) opts
      )
    );

  # methods is a built-in collection — user collections are additional.
  #
  # Hoisted out of mkSchemaEntryType so the entry type and mkSchemaOption's published
  # `_collectionKeys` share ONE derivation rather than two spellings of one contract.
  # The reserved-key refusal stays INSIDE this body deliberately: a read of the
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

      offending = builtins.filter (k: merged ? ${k}) reservedCollectionKeys;
    in
    if offending != [ ] then
      throw "gen-schema: collection '${builtins.head offending}' is reserved — cannot be used as a collection key"
    else
      merged;

  # ── THE KIND-DECLARATION KEY SPACE (den-hoag-nn4) ─────────────────────────────────────────────
  #
  # A key on a kind declaration that NO reader consumes is discarded unread, and the discard is
  # invisible to every instrument this library owns — a typo'd `roel` produces an instance
  # byte-identical to one declared without it, `id_hash` included. ADR-0025 item 1: every operation
  # returns a value or a NAMED refusal.
  #
  # ★ WHAT "UNREAD" MEANS IS ESTABLISHED AT THIS LIBRARY'S OWN READERS, NOT AT gen-merge's
  # `configOf`. `mkSchemaEntryType`'s merge runs three readers of its own over the raw defs,
  # upstream of any module evaluation — `extractedCollections`, `computedFields` and the `mkType`
  # branch — and each consumes top-level keys `configOf` never sees. A predicate derived from
  # `configOf`'s domain FALSE-REFUSES keys this library just read.

  # gen-merge's structural-classification set, RESTATED rather than imported: `markers` is a private
  # binding of its `lib/modules.nix` and its public lib exports none of it (32 members, measured —
  # no marker and no module-key surface). Copying an ENFORCED contract would be the defect
  # `den-hoag-4kh.53.55` rejected; this list is not enforced against gen-merge, and it errs SAFE by
  # construction — a marker omitted here makes a def read as UNSTRUCTURED, so the guard under-fires.
  # A missed refusal, never a false one.
  declarationMarkers = [
    "config"
    "disabledModules"
    "freeformType"
    "imports"
    "options"
  ];

  # `configOf`'s unstructured strip list is `[ key _file _module __pureModule ]`. Three of the four
  # carry the `_` prefix and are admitted by the prefix rule below; `key` is the one that does not.
  declarationMetaKeys = [ "key" ];

  # Published as `schema._declarationKeys` — ONE derivation read by the guard and by the option,
  # never two spellings of one contract. It is a LIST because the enforced finite part of the
  # contract IS a finite list; the prefix rule and the option-declaration rule are NOT lists and go
  # in the option's description instead.
  declarationKeys = prelude.sort (a: b: a < b) (declarationMarkers ++ declarationMetaKeys);

  # ★ THE NAMES `mkSchemaEntryType` WRITES ONTO THE KIND VALUE, each with the writer that earns
  # it. RESTATED for the reason `declarationMarkers` is: the record is built inside the merge body
  # while `mkAllCollections` runs outside it, so it cannot be read off the result. A name omitted
  # here is an UNDER-fire — a missed refusal, never a false one — and the §3b census is what keeps
  # it from drifting.
  kindResultKeys = [
    "__functor" # the importable-module wrapper, default branch
    "kind" # `prelude.last loc`, both branches
    "mixins" # the declared mixin list, default branch
    "strict" # the `strict` formal, both branches
    "keySemantics" # the `keySemantics` formal, both branches
    "options" # `introspect.options`, both branches
    "refs" # `introspect.refs`, both branches
    "refinements" # `extractedRefinements` default branch, `refinementsOfOptions customOptions` mkType branch
    # Written AFTER `// finalCollections` and refused for the REVERSE reason: the mark is applied
    # last, so a collection of that name is SILENTLY OVERWRITTEN — something vanishes and nothing
    # says so. Kept verbatim from the door's own third clause.
    "__mint"
  ];

  # ★ THE COLLECTION KEY SPACE'S RESERVED SET (den-hoag-6vgwm). A caller-supplied collection NAME
  # lands in a key space gen-schema already occupies, and the collision bites in TWO places, both
  # inside `mkSchemaEntryType`'s own merge:
  #
  #   (A) THE DEF-SIDE STRIP. `strippedDefs` runs `removeAttrs d.value collectionKeys` over every
  #       def BEFORE `base.merge`, so a collection named for a module key gen-merge reads deletes
  #       that key from the declaration and gen-merge never receives it. Measured: `collections.
  #       options` deletes the kind's option MODULE while `kind.options` still advertises it, and
  #       the instance's `id_hash` moves — a different node under ADR-0016 ruling 5, silently.
  #       `collections.config` reverts a declared `config.role = "web"` to its default by the same
  #       route. That is why the set is `declarationKeys ++ kindResultKeys` and not the latter
  #       alone: case (A) is reachable on BOTH branches, unconditionally.
  #   (B) THE RESULT-SIDE SHADOW. `// finalCollections` splats over the written kind record, so
  #       every name in `kindResultKeys` is shadowable.
  #
  # ONE DOOR AT THE SOLE CONSTRUCTOR rather than a filter at each consumer: `mkAllCollections` is
  # the only path into the collection key space (`allCollections` and `_collectionKeys`), so the
  # colliding set never forms and `strippedDefs`, `finalCollections` and `markOf` each receive a
  # sound input rather than a checked one.
  #
  # The refusal names ONE key and says nothing about WHY it is reserved: the reason is per-name
  # (two of them, fourteen names) and the caller's remedy is the same for all — rename the
  # collection. A maintainer reads the reason here, at the site they would edit.
  #
  # ★ UNIFORM ACROSS BOTH BRANCHES, at a stated cost. On the `mkType` branch `finalCollections` is
  # never splatted into the result, so `mixins`, `refs` and `refinements` are inert there and
  # refusing them over-fires by three names. `reservedDeclarationKeysFor` branches on `mkType`
  # because `__functor` is LEGITIMATE on that branch; none of these three is legitimate as a
  # collection on either, so one list is taken over two.
  reservedCollectionKeys = prelude.sort (a: b: a < b) (
    prelude.unique (declarationKeys ++ kindResultKeys)
  );

  isStructuredDecl = v: builtins.isAttrs v && prelude.any (k: v ? ${k}) declarationMarkers;

  # ★ THE NAMES THIS LIBRARY WRITES ONTO THE KIND VALUE ITSELF. They begin with `_`, so the prefix
  # rule would admit them as "consumer-private metadata gen-schema must not read" — and they are the
  # opposite of that. The population is READ OFF the merge result's own key set, not assumed:
  # `[ __functor __mint ]` on the default branch and `[ __mint ]` on the `mkType` branch, since that
  # branch declares no `__functor`. Measured at `1ce3eef`: a declared `__mint` does not survive and
  # the kind's own mark is byte-identical with and without it; a declared `__functor` is applied by
  # gen-merge's module classifier and DELETES the rest of the declaration (`options` ⇒ `[ ]` against
  # `[ "role" ]` on the clean twin). Same class, same strength and same shape as the three reserved
  # COLLECTION keys `mkAllCollections` refuses above.
  #
  # ★ WHAT THIS DOOR IS FOR, stated precisely because the obvious reading is wrong. It does NOT
  # repair a swallow that some earlier door was doing `__`-specifically: before this guard existed
  # there was no declaration-key door at all, and a bare `__mint` and a bare `mint` vanished exactly
  # alike, at every revision, mark or no mark. What it does is make these two names LEGIBLE to rule
  # 4, which would otherwise exempt them for carrying the very prefix that marks a key as none of
  # gen-schema's business. Without it, `mint` would refuse and `__mint` would not.
  reservedDeclarationKeysFor =
    mkType:
    if mkType == null then
      [
        "__functor"
        "__mint"
      ]
    else
      [ "__mint" ];

  # The surplus keys of ONE def value — the keys no reader consumes. Each clause names the reader
  # that earns it; `mkSchemaOption`'s `_declarationKeys` option below publishes the same contract.
  surplusDeclarationKeys =
    {
      computed,
      mkType,
    }:
    collectionKeys: v:
    # CLAUSE A · a schema that hands raw or stripped defs to a CALLER-SUPPLIED FUNCTION has no
    # closed key space this library can know, so the guard stands down entirely. TWO premises, and
    # the second is not redundant: the reader-set derivation says `computed` receives the raw `defs`
    # and `mkType` receives `strippedDefs`; gen-aspects' `mkType` then consumes THE WHOLE DEF AS A
    # MODULE (`gen-aspects/lib/schema.nix`, binding `schemaOpt`), so the space is not merely unknown
    # to us — it is unbounded, and no finite allow-list could express it.
    if computed != null || mkType != null then
      [ ]
    # CLAUSE B · on an UNSTRUCTURED def gen-merge's `configOf` reads EVERY key as config, so there
    # is nothing unread to refuse. This is what lets a live consumer's shorthand declarations pass.
    else if !(isStructuredDecl v) then
      [ ]
    else
      # A top-level option declaration is NOT among the read keys: a kind entry is a module, and
      # neither gen-merge nor nixpkgs collects a top-level `mkOption` as a declaration, so it is
      # refused here like any other unread key. `options` is the one place an option is declared.
      # Scoped to the kind entry: a mixin `baseModule` is a RECORD, and `bridge.nix`'s `emitModule`
      # is the typed record→module boundary that lifts its flat option records soundly.
      builtins.filter (
        k:
        # RULE 4 · any key beginning with `_` is consumer-private metadata this library must not
        # read. A PREFIX rule, not a list: it admits every present and future `_`-prefixed module
        # metadata key gen-merge adds, and gen-schema already enforces `_` as its reserved prefix
        # one plane up (`reservedKindNames`, below). The reserved names above are its one exception
        # and are refused by their own door, before this predicate runs.
        !(prelude.hasPrefix "_" k)
        # RULES 1-3 · this schema's collection keys (reader: `extractedCollections`), gen-merge's
        # five structural markers (readers: `configOf`, `optionsOf`, `importsOf`, `topFreeformOf`)
        # and the `key` metadata name (reader: `configOf`'s unstructured strip list).
        && !(builtins.elem k (declarationKeys ++ collectionKeys))
      ) (prelude.attrNames v);

  # Names EVERY offending key on the first offending def, never just the first — a three-typo
  # migration is otherwise three round trips. The recognised sets are RENDERED FROM the bindings the
  # predicate reads, never restated as literals in the string, so they cannot drift out of step.
  unknownDeclarationKeyRefusal =
    kind: collectionKeys: unknown: file:
    let
      noun = if builtins.length unknown == 1 then "key" else "keys";
      named = builtins.concatStringsSep ", " (map (k: "'${k}'") unknown);
      first = builtins.head unknown;
    in
    "gen-schema: kind '${kind}': unrecognised declaration ${noun} ${named} (declared in ${file}). "
    + "This declaration is structured — it carries a module marker — so gen-schema reads only: "
    + "this schema's collection keys "
    + "[${builtins.concatStringsSep ", " collectionKeys}] (published as `schema._collectionKeys`), "
    + "the module keys [${builtins.concatStringsSep ", " declarationKeys}] "
    + "(published as `schema._declarationKeys`), and any `_`-prefixed key. Every other key is "
    + "discarded unread. Declare '${first}': `options.${first} = mkOption { … };` for an option, "
    + "`config.${first} = …` for a value on an option already declared, `_${first}` for "
    + "consumer-private metadata gen-schema must not read, or `${first}` as a collection on "
    + "mkSchemaOption for schema-level data.";

  mkSchemaEntryType =
    {
      baseModule ? null,
      collections ? { },
      computed ? null,
      mixins ? [ ],
      mkType ? null,
      strict ? true,
      keySemantics ? { },
      # BASE MODULE ARGS for the KIND TREE — `introspect` and the `mkType` arm's `customOptions`
      # below, and nothing else in this file.
      #
      # ★ A KIND'S OWN OPTION TREE RECURSES WITHOUT ANY INSTANCE, which is why this is a separate
      # channel from `mkInstanceType`'s and not a duplicate of it. A kind module that forces an
      # argument WHILE DECLARING an option is applied by `introspect`'s `evalModuleTree`, on a kind
      # with no instances anywhere — so the instance constructor is not on that path at all and
      # threading it alone leaves this arm diverging.
      #
      # ★ NO `withArgs` HERE, AND THAT IS THE DESIGN RATHER THAN AN EXCEPTION TO IT. The type-level
      # inlet exists because at a `types.submodule` site the args would otherwise have to arrive as
      # a constructor ATTRSET, and `isModuleValue` admits any attrset, so the misread is silent.
      # `introspect` calls the engine DIRECTLY — there is no type for a method to hang on and no
      # module/parameter ambiguity to resolve — so the channel is `evalModuleTree`'s own published
      # `specialArgs ? { }` formal, reached by an ordinary named formal. One vocabulary, two shapes,
      # each forced by what is in the way at its site.
      specialArgs ? { },
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

          # ── THE DECLARATION-KEY GUARD (den-hoag-nn4) ──────────────────────────────────────────
          #
          # ★ PLACEMENT, which is what applying it to the merge RESULT buys — not coverage. The
          # conditional IS the result, so forcing any field of the kind meets it, and both branches
          # are reached the same way. It does not follow that both branches REFUSE: clause A stands
          # the unknown-key predicate down whenever `computed` or `mkType` is present, so on the
          # `mkType` branch no input is ever named. What is live on both branches is the reserved
          # door below, because `__mint` is written there too.
          #
          # Forcing the result to WHNF forces the conditional, which is what makes a `builtins.seq`
          # unnecessary. The guard is sited HERE, in the descriptor's own `merge` body, rather than
          # on a completed type: gen-merge's `mkOptionType` maps a foreign descriptor's `merge` onto
          # the internal `mergeDefs` and every container dispatches on that, so a `t // { merge = …; }`
          # override is silently ignored.
          reservedNamed = prelude.concatMap (
            d:
            if builtins.isAttrs d.value then
              builtins.filter (k: d.value ? ${k}) (reservedDeclarationKeysFor mkType)
            else
              [ ]
          ) defs;

          surplusOffenders = builtins.filter (
            d: surplusDeclarationKeys { inherit computed mkType; } collectionKeys d.value != [ ]
          ) defs;

          checkDeclarationKeys =
            result:
            if reservedNamed != [ ] then
              throw "gen-schema: kind '${kind}': declaration key '${builtins.head reservedNamed}' is reserved — gen-schema writes it onto every kind value and a declared one is discarded unread"
            else if surplusOffenders != [ ] then
              let
                offender = builtins.head surplusOffenders;
              in
              throw (
                unknownDeclarationKeyRefusal kind collectionKeys (surplusDeclarationKeys {
                  inherit computed mkType;
                } collectionKeys offender.value) (offender.file or "<unknown>")
              )
            else
              result;
        in
        checkDeclarationKeys (
          if mkType != null then
            # Custom entry type: collection extraction runs first (above),
            # then mkType controls the result. The mixin pipeline and __functor
            # wrapping are skipped; `refinements` is DERIVED, from the option plane
            # of the value an instance of this kind imports.
            # Precedence: computedFields wins over mkType result for same-named keys,
            # so computed topology/meta fields remain authoritative.
            # strippedDefs are passed so mkType implementations can wire user-declared
            # options/config from the schema kind entry into their own type systems.
            let
              custom = mkType {
                kindModule = resolvedBase;
                collections = extractedCollections;
                defs = strippedDefs;
                inherit kind;
              };
              published = {
                inherit strict keySemantics;
                options = { };
                refs = { };
              };
              # The option plane an instance sees: `mkInstanceType` imports the PUBLISHED kind
              # value, so the plane is evaluated over the `mkType` result with the published
              # literals and computed fields applied — never over the raw result, whose own
              # `options` key the published `options = { }` overwrites. `specialArgs` and the
              # `_module` filter as `introspect` threads them. The two derived fields
              # (`refinements`, `__mint`) are left out; neither is a module declaration.
              #
              # LAZY, and load-bearing: one `evalModuleTree` per `mkType` kind, memoised in the
              # kind record and forced only by a read of `refinements` — never by `kind` or
              # `__mint.minted`.
              #
              # The module is named for its kind, so a refusal of its syntax (a surplus key beside
              # the published `options`) says which kind to fix; a `_file` of the result's own wins.
              customOptions =
                prelude.filterAttrs (n: _: !(prelude.hasPrefix "_module" n))
                  (merge.evalModuleTree {
                    modules = [
                      ({ _file = "<gen-schema mkType kind ${kind}>"; } // custom // published // computedFields)
                    ];
                    inherit specialArgs;
                  }).options;
            in
            custom
            // published
            // {
              refinements = refinementsOfOptions customOptions;
            }
            // computedFields
            // {
              # `kind` is the LET-BOUND `prelude.last loc` — the option path, which is
              # authoritative — never the `mkType` result's echo of it, which is caller data.
              # The arm publishes `options` and `refs` as the literals above, so those components
              # of the preimage are empty by construction. `refinements` is derived above, but its
              # preimage component stays `[ ]` on this arm: the mark does not read the option
              # plane here, and whether it should is an owner ruling not yet made (den-hoag-mx07b
              # §4 Q1). `ci/tests/mktype-refinements.nix` pins that state.
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

              # Refinements are a PROJECTION of the option plane, read off the same `introspect.options`
              # `refs` is, so `attrNames refinements ⊆ attrNames options` holds by construction and no
              # option can land without its contract, nor a contract without its option. A second,
              # syntactic reader of the raw defs is what let the two planes disagree. On the mixin path
              # the bridge's record refinements are unioned in: its keys are lifted into `options`, so
              # the inclusion still holds, and a contract declared in the kind entry itself is read too.
              # Lazy: forced only when `refinements` is, and that must stay so.
              # Stored on the kind result so mkInstanceRegistry can consume them automatically.
              extractedRefinements =
                (if mixinResult != null then mixinResult.refinements else { })
                // prelude.filterAttrs (_: v: v != [ ]) (
                  prelude.mapAttrs (_: o: getRefinements o.type) (
                    prelude.filterAttrs (_: o: isOptionDecl o && o ? type) introspect.options
                  )
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
                  dummy = merge.evalModuleTree {
                    modules = [ merged ];
                    inherit specialArgs;
                  };
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
            }
        );
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
      # Forwarded VERBATIM to the entry type, which is what builds the kind tree. Same formal, same
      # name, one hop — the schema option itself needs no args, because its own submodule declares
      # only this library's introspection options and never a caller's module.
      specialArgs ? { },
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
              specialArgs
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
          # Published for the reason its two siblings are (`den-hoag-4kh.53.55`): consumers
          # hardcode what a library does not publish, and a consumer that GENERATES collection
          # names — which gen-aspects' caller-supplied cnf makes reachable — needs the set it must
          # avoid without re-deriving it from this file. Single-line description for the reason
          # `_declarationKeys`' is.
          options._reservedCollectionKeys = merge.mkOption {
            type = merge.types.listOf merge.types.str;
            internal = true;
            readOnly = true;
            description = "The collection names `mkSchemaOption` refuses, by name, at construction: gen-merge's structural markers plus the `key` metadata name (a collection of that name would delete the key from every kind declaration before the module merge sees it) together with the names gen-schema writes onto the kind value itself (a collection of that name would shadow what this library wrote, or — for `__mint`, applied last — be silently overwritten by it). The remedy for all of them is the same: rename the collection.";
          };
          # Published for the reason `_collectionKeys` was (`den-hoag-4kh.53.55`): consumers
          # hardcode what a library does not publish. The LIST is only the finite, enforced part of
          # the contract; the two rules that are not lists are stated here and NOT published as
          # lists, which is exactly the narrower-than-enforced defect that ruling rejected.
          options._declarationKeys = merge.mkOption {
            type = merge.types.listOf merge.types.str;
            internal = true;
            readOnly = true;
            # A single-line string rather than a multi-line block, deliberately, and the comment
            # avoids the block delimiter for the same reason: `ci/tests/purity.nix`'s
            # `test-strip-premise-multiline-strings` enumerates the library files containing it —
            # over the RAW source, comments included — because its comment stripper is line-based
            # and a multi-line string is where that premise could break. Matching `_collectionKeys`
            # above costs nothing and leaves that census's population where it was.
            description = "The admissible non-collection keys of a kind declaration: gen-merge's five structural markers plus the `key` metadata name. A structured declaration — one carrying any of those markers — is read ONLY through this set, this schema's `_collectionKeys`, and one rule that is not a list: any key beginning with `_` is admitted as consumer-private metadata gen-schema must not read. An option is declared under `options`; a bare top-level option declaration is not read, because neither module engine collects one, and is refused like any other key. Every other key on a structured declaration is refused by name. Two exceptions to the `_` prefix rule, refused by name because gen-schema writes them onto every kind value and a declared one is discarded unread: `__mint` always, and `__functor` on a schema built without `mkType`. The guard stands down entirely for a schema constructed with `computed` or `mkType`, whose caller-supplied function receives the raw or stripped defs and so owns a key space gen-schema cannot enumerate. An UNSTRUCTURED declaration carries no marker, every key of it is read as config, and none is refused.";
          };
          config =
            let
              # A kind name is any config key that is not one of this submodule's own
              # declared introspection options (_kindNames, _topology, etc. above) — those
              # carry `internal = true`, the same shared per-option marker docs.nix and
              # codec.nix read to separate internal fields from user
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
              # Likewise ONE derivation with the guard's own predicate.
              _declarationKeys = declarationKeys;
              _reservedCollectionKeys = reservedCollectionKeys;
            };
        }
      );
    };
in
{
  inherit mkSchemaEntryType mkSchemaOption isSchemaKind;
}
