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
  componentsPreimage,
  sealedCollisionEq,
  identityOf,
  comparisonSubject,
  constructionRelation,
  keySemanticsRecords,
}:
let
  # ★ THE PROVENANCE MARK (ADR-0034), minted at the ONE site every kind value reaches — both
  # declaration shapes arrive at `mkSchemaEntryType`'s merge, `mkSchemaOption` directly and
  # gen-aspects through `genSchema.mkSchemaOption`. It is what makes "this value came out of a
  # schema" a CHECKABLE property instead of a shape heuristic: the `? kind && ? options` guard it
  # replaces admitted any hand-written attrset, so every message naming a kind value named a
  # provenance its own predicate never looked at.
  #
  # MINTED over the kind's name, its `strict` flag and its distinguishing CONTENT as per-component
  # preimage tags (`planeOf` below): a minted component by its digest, an inert one whole, one
  # with no value at WHNF as `undefined`, and a lambda, an unmigrated type or anything else the
  # mint refuses as the SEALED MARKER (ADR-0034's REFUSED regime, applied per component). A
  # lambda's body and captured environment are exposed by no builtin (ADR-0013), so two kinds
  # differing only at a sealed component share a mark; `kindEq` then refuses the pair BY NAME
  # rather than calling them one kind, reading the sealed subjects the same call produced.
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
  # ★ (c+), den-hoag-markof-partial-preimage-znfjq. THE KIND'S DISTINGUISHING CONTENT, as
  # components, from ONE plane per arm — the option tree, its kind-level config, the
  # collections, `keySemantics`, `refs` and the computed fields. `markOf` mints over the
  # components' TAGS and the kind value carries their SEALED subjects (`__sealed`) for `kindEq`;
  # both come out of one `componentsPreimage` call, so the two cannot read different planes.
  #
  # EVERY attribute of an option declaration is a component, the presentation keys (`description`,
  # `example`, `defaultText`, …) included: an instance module is handed `options` and can read
  # `options.port.description` into its config, so no attribute is outside the merged result (the
  # a0gc standard: exclusion owes that argument, and none holds). The declaration's `freeformType`,
  # at either site (top-level or `_module.freeformType`), is a component too: it decides which
  # undeclared instance keys are accepted. Four exclusions, each a projection of a
  # component already present (ADR-0013, a derivable fact is derived once): `refinements`
  # (`refinementsOfOptions` of the option types), `mixins` (their whole effect is the option and
  # config plane the bridge emits, and any function it carries is walked as an opaque module),
  # `baseModule` (its value for THIS kind is the resolved module, walked below) and `specialArgs`
  # (they reach a kind only through a function module, and every function module is a sealed
  # component). `mkType` and `computed` are components, sealed by constructor: what they add that
  # the plane cannot evaluate lives only in their bodies.
  #
  # A TYPE the mint cannot mint (a field's, a freeform's, a facet's, a ref's: unmigrated, or carrying
  # no minted identity) is sealed here rather than handed to the encoder, so no type record is forced
  # to decide it, and it is compared through `comparedTyped` below.
  #
  # A declaration's modules, found through `imports` at any depth, split by whether the plane can
  # see into them. An OPAQUE module — a function module, a functor, a path — is one the plane
  # cannot see into: what it contributes that the kind level cannot evaluate (a definition reading
  # an instance's config) lives only in its body, so the body is a component. An attrset module
  # is not opaque: its `options` and `config` are the option plane and the kind-level values
  # themselves, and its `freeformType` is read off it here (the evaluated tree does not publish
  # the resolved one).
  modulesOf = prelude.concatMap (
    v:
    if v == null then
      [ ]
    else if builtins.isAttrs v && !(v ? __functor) then
      [ { open = v; } ] ++ modulesOf (v.imports or [ ])
    else
      [ { opaque = v; } ]
  );
  # A type record with no minted identity, unmigrated or unmintable: the mint refuses it either way,
  # so declaring it sealed moves no tag. The REGIME is still the mint's per-component tag
  # (den-hoag-markof-partial-preimage-znfjq, ruling (c+): decided by the mint unless the constructor
  # declares it) — this reads it, it does not declare it; what the grammar declares is the POSITION
  # of the records (`recordsOf` below), which is what `comparedTyped` needs.
  isSealedType = t: !(builtins.isAttrs t) || !(identityOf t ? minted);

  # ★ THE COMPARED SUBJECT OF A SEALED COMPONENT HOLDING TYPE RECORDS (den-hoag-6b5ia). A type record
  # is cyclic (`functor.type`), so a bare `==` between two constructions can recurse until the
  # evaluator aborts, uncatchably, past `sealedCollisionEq`'s `tryEval`. `records` are the type
  # records this plane's grammar places in `v`; gen-merge's `closuresFirst` decides on their closures
  # first, the subject `constructionRelation` compares by (den-hoag-bfc0k). A member of `records`
  # that is not a record (`type = "str"`) contributes no closures there. The accessor `__id` is
  # dropped as `componentsPreimage` drops it from a bare value. The four positions: an option's
  # `type`, the declaration's `freeformType`, a `keySemantics` entry's `option.type`
  # (`keySemanticsRecords`) and a `refs` entry's `type`.
  #
  # COST: tags and marks are unchanged. The subject is a thunk in `__sealed`, forced only on the
  # equal-mark path of `kindEq` (and gen-select's `selectorEq`), where `closuresOf` allocates one
  # attrset per record.
  #
  # ★ ENUMERATED EXCEPTION TO TOTALITY (ADR-0025 item 1). `kindEq` can still abort where the closures
  # prefix is EQUAL and the value reaches a back-edge before a difference: (1) a GRAFT sharing every
  # closure slot and holding distinct cyclic data elsewhere (`closuresFirst`'s exception 1); (2) a
  # cyclic value at a position this grammar does not fix — an option's `description`, `default`
  # (a type record there included) or `example`; content of a `keySemantics` entry outside
  # `option.type` (the option's own `description`, a type under any other key); a collection member;
  # a functor module. Closing it without moving a value needs an evaluator-observable value identity
  # (a visited set), which pure Nix does not expose; a bounded finiteness walk closes it at a value
  # move (den-hoag-8owed arm G, owed an owner reading). This enumeration is 8owed's arm (A),
  # defaulted, reversible.
  comparedTyped =
    records: v:
    merge.closuresFirst records (if builtins.isAttrs v && v ? __id then comparisonSubject v else v);

  planeOf =
    {
      options,
      config,
      collections,
      keySemantics,
      refs,
      computed,
      modules,
      functions,
    }:
    let
      optionComponents =
        prefix: opts: cfg:
        prelude.concatMap (
          n:
          let
            o = opts.${n};
            p = prefix ++ [ n ];
          in
          if isOptionDecl o then
            map (
              a:
              if a == "type" && isSealedType o.type then
                {
                  path = [ "options" ] ++ p ++ [ a ];
                  value = comparedTyped [ o.type ] o.type;
                  sealed = true;
                }
              else
                {
                  path = [ "options" ] ++ p ++ [ a ];
                  value = o.${a};
                }
            ) (prelude.attrNames o)
            ++ [
              {
                path = [ "value" ] ++ p;
                value = cfg.${n};
              }
            ]
          else
            optionComponents p o cfg.${n}
        ) (prelude.attrNames opts);
      # An attrset-valued component is spread one level, so a refusal names the member (a method,
      # a category) rather than the whole collection; its key set stays a component of its own.
      # `recordsOf` names the type records a member's grammar holds; a member holding a sealed one is
      # declared sealed and compared through `comparedTyped`, and every other member is left to the mint.
      spread =
        prefix: recordsOf: v:
        let
          isRecord = builtins.tryEval (
            builtins.isAttrs v && identityOf v ? unmigrated && (v.type or null) != "derivation"
          );
        in
        if isRecord.success && isRecord.value then
          [
            {
              path = prefix;
              value = prelude.attrNames v;
            }
          ]
          ++ map (
            k:
            let
              records = recordsOf v.${k};
              typed = builtins.tryEval (builtins.any isSealedType records);
            in
            if typed.success && typed.value then
              {
                path = prefix ++ [ k ];
                value = comparedTyped records v.${k};
                sealed = true;
              }
            else
              {
                path = prefix ++ [ k ];
                value = v.${k};
              }
          ) (prelude.attrNames v)
        else
          [
            {
              path = prefix;
              value = v;
            }
          ];
      walked = modulesOf modules;
      open = map (m: m.open) (builtins.filter (m: m ? open) walked);
      freeforms = builtins.filter (t: t != null) (
        prelude.concatMap (m: [
          (m.freeformType or null)
          ((m._module or { }).freeformType or null)
          (((m.config or { })._module or { }).freeformType or null)
        ]) open
      );
    in
    componentsPreimage identity.hashIdentity (
      optionComponents [ ] options config
      ++ [
        {
          path = [ "collectionNames" ];
          value = prelude.attrNames collections;
        }
      ]
      ++ prelude.concatMap (c: spread [ "collections" c ] (_: [ ]) collections.${c}) (
        prelude.attrNames collections
      )
      ++ spread [ "keySemantics" ] (e: keySemanticsRecords { inherit e; }) keySemantics
      # A ref entry is `{ refKind; type; }` (ref.nix `refsFromOptionsWithTypes`).
      ++ spread [ "refs" ] (e: [ e.type ]) refs
      ++ spread [ "computed" ] (_: [ ]) computed
      ++ [
        {
          path = [ "modules" ];
          value = map (m: m.opaque) (builtins.filter (m: m ? opaque) walked);
        }
        (
          if builtins.any isSealedType freeforms then
            {
              path = [ "freeformType" ];
              value = comparedTyped freeforms freeforms;
              sealed = true;
            }
          else
            {
              path = [ "freeformType" ];
              value = freeforms;
            }
        )
      ]
      # The schema's own functions are sealed BY CONSTRUCTOR — declared, never forced.
      ++ map (n: {
        path = [
          "functions"
          n
        ];
        value = functions.${n};
        sealed = functions.${n} != null;
      }) (prelude.attrNames functions)
    );

  markOf =
    {
      kind,
      strict,
      plane,
    }:
    identity.hashIdentity "schemakind"
      [
        "kind"
        "plane"
        "strict"
      ]
      (
        l:
        {
          inherit kind strict;
          plane = plane.tags;
        }
        .${l}
      );

  # THE DOOR a consumer compares kinds through (c+): `true` iff two kind values carry one identity,
  # `false` if two, and a refusal BY NAME where they mint one identity and differ only at a sealed
  # component (ADR-0034: "that component's collapse is replaced by a refusal"). An operand that is
  # not a kind value is refused by name, as the four admission guards refuse it.
  kindEq =
    let
      subject =
        k:
        if isSchemaKind k && k ? __sealed then
          {
            name = k.kind;
            mark = k.__mint.minted;
            sealed = k.__sealed;
          }
        else
          throw "gen-schema: kindEq: expected a kind value carrying a mint-backed mark (`__mint.minted`); got ${
            if builtins.isAttrs k then "an attrset with no mark" else builtins.typeOf k
          }";
    in
    a: b: sealedCollisionEq "gen-schema: kindEq" (subject a) (subject b);

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
    "refinements" # `extractedRefinements` default branch, `refinementsOfOptions introspect.options` mkType branch
    # Written AFTER `// finalCollections` and refused for the REVERSE reason: the mark is applied
    # last, so a collection of that name is SILENTLY OVERWRITTEN — something vanishes and nothing
    # says so. Kept verbatim from the door's own third clause.
    "__mint"
    # Written beside `__mint` and refused for the same reason: the sealed subjects `kindEq` reads.
    "__sealed"
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
  # (two of them, fifteen names) and the caller's remedy is the same for all — rename the
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
        "__sealed"
      ]
    else
      [
        "__mint"
        "__sealed"
      ];

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
      # BASE MODULE ARGS for the KIND TREE — `introspectOf` below, which both arms read, and
      # nothing else in this file.
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

      # ONE introspection for both arms: the option tree an instance imports, its kind-level config
      # and its refs, from one `evalModuleTree` over the module an instance imports. Each arm
      # publishes `options` and `refs` from it and `planeOf` and `refinements` read the same
      # binding, so the published plane, the mark and `__sealed` are one plane.
      #
      # Lazy: evaluated on first access of `options`, `refs`, `refinements` or the mark. Each arm
      # passes a locally-built module, never `config.${k}`, to avoid circularity.
      introspectOf =
        module:
        let
          tree = merge.evalModuleTree {
            modules = [ module ];
            inherit specialArgs;
          };
          options = prelude.filterAttrs (n: _: !(prelude.hasPrefix "_module" n)) tree.options;
        in
        {
          inherit options;
          inherit (tree) config;
          refs = refsFromOptionsWithTypes options;
        };

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

      # THE CONSTRUCTION, for the entry type's merge relation (den-hoag-bfc0k). The type is a
      # function of these formals and nothing else, so each is a component, and its regime is
      # declared here, by constructor, never read off the value (ADR-0034). `strict` is inert by
      # construction and is minted. Every other formal can carry a caller's function — a
      # collection's `merge`, a mixin, a function `baseModule`, a facet module in `keySemantics`,
      # anything in `specialArgs`, and `computed`/`mkType` themselves — so each is COMPARED, as
      # its reified value under Nix `==`, which is structural over inert content and identity
      # over a function. A formal missing here would be dropped from the relation and two
      # different entry types would merge, so the list is checked against the formals. Each value
      # is handed over as `{ records; value; }` and `constructionRelation` binds `value` by a
      # formal, keeping the slot this constructor passed: upstream Nix `==` keeps a function's
      # identity only for one slot, and a selection is a fresh one (den-hoag-jzatq), so one shared
      # `computed` passed to two calls would otherwise be refused on Nix and merged on Lix.
      components =
        let
          open = value: {
            records = [ ];
            inherit value;
          };
          cs = {
            minted = { inherit strict; };
            compared = {
              keySemantics = {
                records = keySemanticsRecords keySemantics;
                value = keySemantics;
              };
              collections = open collections;
              mixins = open mixins;
              baseModule = open baseModule;
              specialArgs = open specialArgs;
              computed = open computed;
              mkType = open mkType;
            };
          };
          named = prelude.sort (a: b: a < b) (prelude.attrNames cs.minted ++ prelude.attrNames cs.compared);
          formals = prelude.attrNames (builtins.functionArgs mkSchemaEntryType);
        in
        if named == formals then
          cs
        else
          throw "gen-schema: mkSchemaEntryType's construction components [${builtins.concatStringsSep ", " named}] are not its formals [${builtins.concatStringsSep ", " formals}]";
    in
    # Built THROUGH mkOptionType rather than as `base // { merge = …; }`. An override over an
    # already completed type answers the protocol as its LEFT operand, so the entry type would
    # carry deferredModule's name, its description and — the one that bites — its functor, whose
    # `type` points back at the plain deferredModule. A typeMerge over two declarations of one
    # `lazyAttrsOf` of this type then rebuilds a bare deferredModule and the collection-extracting
    # merge below is gone, silently, with the defs falling through to a plain module import. The
    # entry type is not a deferredModule; it DELEGATES to one (`base.merge`, called inside), and that
    # delegation is the only thing it takes from it.
    #
    # Built per call (`mkSchemaOption` builds one per call and states its own type's relation with
    # this one's payload and binOp), so a redeclared option typed by it meets a second record:
    # `functor` is the relation that merges the two when they are one construction.
    let
      self = merge.mkOptionType {
        name = "schemaKindEntry";
        description = "schema kind entry — options, config, collections and computed fields";
        functor = constructionRelation "schemaKindEntry" components self;
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
                # Every other name this library writes onto the kind value, read off `kindResultKeys`
                # so the door moves with the record. The computed fields are splatted OVER the written
                # record on both branches, so a computed `options` or `refs` silently replaced the
                # published plane (den-hoag-ciu4r, ADR-0025).
                #
                # ★ UNIFORM ACROSS BOTH BRANCHES, at a stated cost — the same shape as
                # `reservedCollectionKeys` above (den-hoag-ciu4r P1, den-hoag-3x3bi). On the `mkType`
                # branch `mkSchemaEntryType` never writes `mixins` (the mixin pipeline runs only on
                # the default branch), so refusing a computed `mixins` there over-fires ALWAYS: it
                # protects nothing this library wrote. `__functor` is written on that branch only
                # when the `mkType` result is itself a functor (`custom ? __functor`, above), so
                # refusing a computed `__functor` over-fires whenever it is not. `kind` is written
                # UNCONDITIONALLY on both branches (the `inherit kind;` beside `__mint`, below) — it
                # is NOT in the over-fire set. One list is taken over two rather than a per-branch
                # set, so a computed `mixins` cannot read back differently between branches for a
                # reason no caller could see.
                shadowing = builtins.filter (k: fields ? ${k}) kindResultKeys;
              in
              # `__mint` is refused here for the reason `mkAllCollections` refuses it as a collection
              # key: the stamp is applied last and would overwrite a computed field of that name
              # without saying so.
              if fields ? __mint then
                throw "gen-schema: computed field '__mint' is reserved — the provenance mark is minted by mkSchemaEntryType"
              else if fields ? __sealed then
                throw "gen-schema: computed field '__sealed' is reserved — the sealed subjects are written by mkSchemaEntryType"
              else if shadowing != [ ] then
                throw "gen-schema: computed field '${builtins.head shadowing}' is reserved — it is part of the kind-value contract; reserved computed-field names: ${builtins.concatStringsSep ", " kindResultKeys}"
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
              # wrapping are skipped; `options`, `refs` and `refinements` are DERIVED, from the
              # option plane of the value an instance of this kind imports.
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
                # The keys the arm applies over the `mkType` result. `options = { }` and `refs = { }`
                # stand in the TREE MODULE only: the kind value publishes the evaluated plane under
                # those names, and a module built over the kind value itself would be circular for any
                # reader of `options` (gen-merge's reader of a non-functor module, or a functor that
                # reads its `self`). The pinned refusal of a non-functor result names `keySemantics`
                # from exactly this module.
                published = {
                  inherit strict keySemantics;
                  options = { };
                  refs = { };
                };
                # The module an instance imports: the `mkType` result with the published keys and
                # computed fields applied. The derived fields (`options`, `refs`, `refinements`,
                # `__mint`, `__sealed`) are left out; none is a module declaration.
                #
                # LAZY, and load-bearing: one `evalModuleTree` per `mkType` kind, memoised in the
                # kind record and forced only by a read of `options`, `refs`, `refinements` or the
                # mark — never by `kind` or `strict`.
                #
                # The module is named for its kind, so a refusal of its syntax (a surplus key beside
                # the published `options`) says which kind to fix; a `_file` of the result's own wins.
                treeModule = {
                  _file = "<gen-schema mkType kind ${kind}>";
                }
                // custom
                // published
                // computedFields;
                introspect = introspectOf treeModule;
                # ONE plane for the published fields, the mark and `kindEq` (c+): this arm's option
                # plane is the tree an instance imports, so it enters the preimage.
                plane = planeOf {
                  inherit (introspect) options config refs;
                  collections = extractedCollections;
                  inherit keySemantics;
                  computed = computedFields;
                  modules = map (d: d.value) strippedDefs ++ [ resolvedBase ];
                  functions = { inherit mkType computed; };
                };
              in
              custom
              // published
              // {
                inherit (introspect) options refs;
                refinements = refinementsOfOptions introspect.options;
              }
              # The result's functor is applied to `treeModule`, so the tree and an instance hand it
              # the same `self` and a functor that reads `self.options` declares one plane in both.
              # Applied before the computed fields, which still win for same-named keys.
              // prelude.optionalAttrs (custom ? __functor) { __functor = _: custom.__functor treeModule; }
              // computedFields
              // {
                # `kind` is the LET-BOUND `prelude.last loc` — the option path, which is
                # authoritative — never the `mkType` result's echo of it, which is caller data.
                # WRITTEN here (den-hoag-3x3bi, ADR-0025): before this, nothing on this arm wrote
                # `kind` at all, so a result carrying none made `.kind` abort uncatchably
                # (`attribute 'kind' missing`, not a `throw` `tryEval` can catch) and
                # `mkInstanceType` refused with the FALSE reason "no mark" (`isSchemaKind` reads
                # `v ? kind` first); a result echoing a WRONG name published that name while the
                # mark stayed keyed to the option path, silently disagreeing with it. Applied AFTER
                # `// computedFields`, beside `__mint`, so a computed `kind` cannot re-open what this
                # write closes — `kind` is refused as a computed-field name below regardless.
                # The mark reads `plane`, the one plane the arm publishes as `options` and `refs`
                # (den-hoag-mx07b §4 Q1 ruled). `ci/tests/mktype-refinements.nix` pins that the mark
                # reads it.
                inherit kind;
                __mint = {
                  minted = markOf { inherit kind strict plane; };
                };
                __sealed = plane.sealed;
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

                introspect = introspectOf merged;
                plane = planeOf {
                  inherit (introspect) options config refs;
                  collections = finalCollections;
                  inherit keySemantics;
                  computed = computedFields;
                  modules = map (d: d.value) strippedDefs ++ [ effectiveBase ];
                  functions = { inherit mkType computed; };
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
                  minted = markOf { inherit kind strict plane; };
                };
                __sealed = plane.sealed;
              }
          );
      };
    in
    self;

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
    let
      # Built once per call. The option's type below is a function of exactly these formals, so
      # the entry's construction IS the option's construction — a premise refused by name if a
      # formal is ever added to one constructor and not the other, since a formal the entry does not
      # take would be absent from its components, and two option types differing only in it would
      # merge silently.
      entry =
        let
          optionFormals = builtins.functionArgs mkSchemaOption;
          entryFormals = builtins.functionArgs mkSchemaEntryType;
        in
        if optionFormals == entryFormals then
          mkSchemaEntryType {
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
          }
        else
          throw "gen-schema: mkSchemaOption's formals [${builtins.concatStringsSep ", " (prelude.attrNames optionFormals)}] are not mkSchemaEntryType's [${builtins.concatStringsSep ", " (prelude.attrNames entryFormals)}]; the schema option's type is its entry type's construction, so the two must take one set";
      inner = merge.types.submodule (
        { config, options, ... }:
        {
          freeformType = merge.types.lazyAttrsOf entry;

          # READ-ONLY, on two measured bases (den-hoag-px98p): a well-typed write to a derived output
          # (`config.schema._collectionKeys = [ "fake" ]`) would otherwise be published silently, and
          # a doubly-imported introspection module would concatenate its `listOf` fields
          # (`[ "k" "k" ]`). A KIND named after one of these options is refused by its type, not by
          # this flag (den-hoag-collectionkeys-collision-oracle-25mae, O6: a companion, not a
          # discriminator).
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
      # ★ THE OPTION'S TYPE STATES ITS OWN MERGE RELATION (den-hoag-px98p). Declared twice, a plain
      # `submodule` concatenates its module lists, so one construction declared twice imported the
      # introspection module twice and every read-only `_`-field refused "defined 2 times". This type
      # DELEGATES to `inner` (check, merge, emptyValue, sub-options) and takes its relation from the
      # entry type's `constructionRelation` payload and binOp: two schema option types are one type
      # exactly when their entry types are one construction (ADR-0034, t ⊔ t = t), and the merge
      # answers with that one type, so every `_`-field is defined once (ADR-0012 item 2: a
      # materialized view of the record, computed once). A pair of different constructions is
      # refused by name at `schema`, within `closuresFirst`'s enumerated exception (a per-call type
      # in module content can still abort; bfc0k gate v1 residual (b), den-hoag-6b5ia).
      #
      # Stated departures: the type is named `schema`, not `submodule`, so a plain `submodule`
      # declared beside it is refused by name, in both orders (it used to union in and have its
      # option misread as a kind); and it carries no `getSubModules`/`substSubModules`, so a foreign
      # engine's `substSubModules` cannot rebuild a plain submodule and drop the relation — gen-merge's
      # declaration-stratum route over `getSubModules` no longer applies to it. The idempotence is a
      # property of gen-merge's engine: nixpkgs `lib.evalModules` still refuses the second
      # declaration.
      self = merge.mkOptionType {
        name = "schema";
        description = "schema — typed record registry";
        inherit (inner)
          check
          merge
          emptyValue
          getSubOptions
          ;
        functor = {
          name = "schema";
          inherit (entry.functor) payload binOp;
          type = _: self;
        };
      };
    in
    merge.mkOption {
      description = "Schema — typed record registry with extension points";
      default = { };
      type = self;
    };
in
{
  inherit
    mkSchemaEntryType
    mkSchemaOption
    isSchemaKind
    kindEq
    ;
}
