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
  graph,
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
  # `builtins.warn` where the evaluator has it (it honours `abort-on-warn`), a trace otherwise.
  warn = builtins.warn or (msg: v: builtins.trace "evaluation warning: ${msg}" v);
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
  # components, from ONE plane per arm — the option tree, the collections, `keySemantics`, `refs`
  # and the computed fields. `markOf` mints over the components' TAGS and the kind value carries
  # their SEALED subjects (`__sealed`) for `kindEq`; both come out of one `componentsPreimage` call,
  # so the two cannot read different planes.
  #
  # Of an option declaration, ONE attribute is a component by value: its `type` (`optionComponents`
  # below). Every other attribute, and every kind-level definition, is a component by PATH only,
  # sealed (`openComponents` below), with `meta` and every kind-level `_module` key but
  # `freeformType`. The declaration's `freeformType`,
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
  # A declaration's modules, found at any depth through the list gen-merge's `importsOf` joins
  # (`imports`, and before it a shorthand module's `require`), split by whether the plane can
  # see into them. An OPAQUE module — a function module, a functor, a path — is one the plane
  # cannot see into: what it contributes that the kind level cannot evaluate (a definition reading
  # an instance's config) lives only in its body, so the body is a component. An attrset module
  # is not opaque: its `options` are the option plane itself, and its `freeformType` is read off it
  # here (the evaluated tree does not publish the resolved one).
  modulesOf = prelude.concatMap (
    v:
    if v == null then
      [ ]
    else if builtins.isAttrs v && !(v ? __functor) then
      let
        i = v.imports or [ ];
      in
      [ { open = v; } ]
      ++ modulesOf (
        (if v ? require && !(isStructuredDecl v) then v.require else [ ])
        ++ (if builtins.isList i then i else [ i ])
      )
    else
      [ { opaque = v; } ]
  );
  # A type record with no minted identity, unmigrated or unmintable: the mint refuses it either way,
  # so declaring it sealed moves no tag. The REGIME is still the mint's per-component tag
  # (den-hoag-markof-partial-preimage-znfjq, ruling (c+): decided by the mint unless the constructor
  # declares it) — this reads it, it does not declare it; what the grammar declares is the POSITION
  # of the records (`recordsOf` below), which is what `comparedTyped` needs.
  isSealedType = t: !(builtins.isAttrs t) || !(identityOf t ? minted);

  # ★ AN OPTION ENTERS THE MARK BY ITS `type` ALONE (den-hoag-pa887, arm A). Every other attribute of
  # a declaration — `default`, `defaultText`, `description`, `example`, `readOnly`, `apply`,
  # `visible`, `internal`, `identity`, any attribute gen-merge does not know — and the option's
  # kind-level VALUE may be written in a function module over an instance's `config`
  # (`default = self + "/${config.name}"` is the ordinary idiom). At kind level that is an open
  # term: `name` is bound only per instance (`mkInstanceType`), so forcing it aborts, uncatchably
  # ("attribute 'name' missing" is no `throw`), and a demanded kind identity becomes partial on a
  # well-formed schema. Whether a given attribute reads `config` is visible only by forcing it, the
  # INSPECTION ADR-0034 excludes ("decided by constructor, never by inspecting a value"), so no
  # attribute outside `type` is forced; `type` was the whole of znfjq's (c+) ruling and is forced by
  # the mint as before. What distinguishes a term written over `config` is its enclosing function
  # module, already a sealed component (`modules`).
  # ⇒ each such attribute, and each kind-level definition, enters by its PATH as a sealed component
  # (den-hoag-egei0, ADR-0034's sealed limb per component): the mark carries the marker, so a kind
  # with a default and one without mint apart, and two kinds whose open paths agree share a mark and
  # are REFUSED BY NAME at `open.*` by `kindEq`, never merged (`kind-mark-cplus`,
  # `test-open-content-*`). ⇒ the COST, a named refusal class: two independent constructions of one
  # declaration carrying open content are refused too (`test-open-content-twin-is-refused`); one
  # kind value with itself is decided. Its only remedy is a sealed-literal constructor that puts an
  # inert literal into the mark.

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
  # cyclic value at a position this grammar does not fix — content of a `keySemantics` entry outside
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
      collections,
      keySemantics,
      refs,
      computed,
      modules,
      functions,
    }:
    let
      optionComponents =
        prefix: opts:
        prelude.concatMap (
          n:
          let
            o = opts.${n};
            p = prefix ++ [ n ];
          in
          # An option with no `type` still enters, as `null`, so the option set stays in the mark.
          if isOptionDecl o then
            let
              t = o.type or null;
            in
            [
              (
                if t != null && isSealedType t then
                  {
                    path = [ "options" ] ++ p ++ [ "type" ];
                    value = comparedTyped [ t ] t;
                    sealed = true;
                  }
                else
                  {
                    path = [ "options" ] ++ p ++ [ "type" ];
                    value = t;
                  }
              )
            ]
          else
            optionComponents p o
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
      # The PATHS of an open module's content beyond an option's `type` (den-hoag-egei0): another
      # attribute of a declaration, a kind-level definition (a structured module's `meta` included,
      # which gen-merge's `configOf` folds into its config), and every kind-level `_module` key but
      # `freeformType` (a component of its own, below). Presence only, read by `attrNames`,
      # `isOptionDecl` and `isAttrs`: no definition value is forced, and the config half stops at the
      # top-level key set, so nothing past the `m.config` WHNF `freeforms` already takes is read.
      # A path carries NO module index and the set is deduplicated: which module states a key is not
      # identity, so a reordered or regrouped twin reaches the same paths and is refused on the
      # subject rather than split by the mark.
      openPaths = builtins.attrValues (
        builtins.listToAttrs (
          map (p: {
            name = builtins.concatStringsSep "." p;
            value = p;
          }) (prelude.concatMap openPathsOf open)
        )
      );
      openPathsOf =
        m:
        let
          s = isStructuredDecl m;
          # gen-merge's `configOf`, at the key level: a structured module's config plus its `meta`,
          # a shorthand module less its module-syntax keys.
          defs =
            if s then
              (m.config or { }) // (if m ? meta then { inherit (m) meta; } else { })
            else
              builtins.removeAttrs m merge.moduleSyntax.shorthandMeta;
          whole = !(builtins.isAttrs defs) || defs ? _type;
          attrsOf =
            pre: t:
            prelude.concatMap (
              n:
              let
                o = t.${n};
                q = pre ++ [ n ];
              in
              if isOptionDecl o then
                map (a: q ++ [ a ]) (builtins.filter (a: a != "type" && a != "_type") (prelude.attrNames o))
              else if builtins.isAttrs o then
                attrsOf q o
              else
                [ ]
            ) (prelude.attrNames t);
          moduleKeys =
            let
              top = m._module or { };
              inner = if whole then { } else defs._module or { };
            in
            builtins.filter (k: k != "freeformType") (
              prelude.attrNames (
                (if builtins.isAttrs top then top else { }) // (if builtins.isAttrs inner then inner else { })
              )
            );
        in
        attrsOf [
          "open"
          "options"
        ] (if s then m.options or { } else { })
        ++ (
          if whole then
            [
              [
                "open"
                "config"
              ]
            ]
          else
            map (n: [
              "open"
              "config"
              n
            ]) (builtins.filter (n: n != "_module") (prelude.attrNames defs))
        )
        ++ map (k: [
          "open"
          "_module"
          k
        ]) moduleKeys;
      # Each is a SEALED component, as a schema's own `functions` are: the mark carries the marker at
      # its path, and its subject is a closure allocated by this call, never equal to another
      # construction's. The content itself is never the subject: comparing it would force it, and a
      # K3 capture aborts uncatchably when forced. A subject is equal to itself only while it is not
      # rebuilt: a kind value carries `__mint`, so gen-merge's `types.anything` carries it whole.
      openComponents = map (p: {
        path = p;
        value = _: p;
        sealed = true;
      }) openPaths;
      freeforms = builtins.filter (t: t != null) (
        prelude.concatMap (m: [
          (m.freeformType or null)
          ((m._module or { }).freeformType or null)
          (((m.config or { })._module or { }).freeformType or null)
        ]) open
      );
    in
    componentsPreimage identity.hashIdentity (
      optionComponents [ ] options
      ++ openComponents
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
      # The schema's own functions are sealed BY CONSTRUCTOR — declared, never forced. Bound by a
      # lambda's formal, never selected: upstream Nix `==` keeps a function's identity only for the
      # one slot it was bound to, and a selection `functions.${n}` is a fresh slot, so one shared
      # `mkType` handed to two constructions would be refused on Nix and merged on Lix
      # (den-hoag-jzatq). The formal IS the attribute's own slot, and `componentsPreimage` carries
      # it into `sealed` unchanged. An absent function is inert and minted as `null`, so the mark
      # does not move.
      ++ builtins.attrValues (
        builtins.mapAttrs (
          n: f:
          let
            sealed = f != null;
          in
          {
            path = [
              "functions"
              n
            ];
            value = f;
            inherit sealed;
          }
        ) functions
      )
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
  # component (ADR-0034: "that component's collapse is replaced by a refusal"). Open-module content
  # beyond an option's `type` is such a component (`openComponents`), so a pair differing there, or
  # two constructions of one declaration carrying it, is refused naming its `open.*` path. An operand
  # that is not a kind value is refused by name, as the four admission guards refuse it. A kind value
  # compared with itself carried through gen-merge's `types.anything` (or `attrsOf`/`listOf
  # anything`) is `true` on every evaluator: `anything` carries a `__mint` carrier whole
  # (`kind-mark-cplus.test-kind-reflexive-under-anything-transport`).
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
  #
  # The shape is ONE BINDING read by two predicates: this one, and `entryReservation`'s `exempt`,
  # which gen-merge's collector tests as data (it cannot call this function). So the alias and the
  # exemption from the imports-route reservation cannot drift apart.
  schemaKindShape = [
    [ "kind" ]
    [
      "__mint"
      "minted"
    ]
  ];
  hasPath =
    p: v:
    p == [ ]
    || (builtins.isAttrs v && v ? ${builtins.head p} && hasPath (builtins.tail p) v.${builtins.head p});
  isSchemaKind = v: builtins.isAttrs v && builtins.all (p: hasPath p v) schemaKindShape;

  # THE RESOLVER'S PROVENANCE (den-hoag-8c8pr). `inherits` has one reader that composes it,
  # `evalSchema`, and it composes a parent by contributing a def to the child. The def carries this
  # `_file`, so the kind entry can tell a declared parent that was resolved from one nothing read —
  # the nn4 discipline (a declaration key no reader consumes is refused, never discarded) applied to
  # a key whose reader depends on how the tree was built. One derivation, read by both files.
  inheritsResolvedFile = kind: parent: "<gen-schema evalSchema: kind '${kind}' inherits '${parent}'>";
  inheritsDesugaredFile = kind: parent: "<gen-schema: kind '${kind}' inherits '${parent}'>";

  # Where a def was written, for a kind's content witness: its first attribute's source position, or
  # its type when it has none (a function or path module, an empty set).
  witnessPos =
    v:
    let
      p =
        if builtins.isAttrs v && v != { } then
          builtins.unsafeGetAttrPos (builtins.head (builtins.attrNames v)) v
        else
          null;
    in
    if p == null then builtins.typeOf v else "${p.file}:${toString p.line}:${toString p.column}";

  # WHAT a resolved parent contributes to its child, on either tree: the parent's MODULE, its
  # `__functor` applied, never its kind value — a kind value in a kind entry's `imports` is the
  # deprecated spelling, which the entry type reads as `inherits` and warns on (den-hoag-cxlc0). One
  # derivation for `evalSchema`'s pass and the unstaged desugar, so the two compose one module.
  inheritedModule =
    kind: parent: v:
    if v ? __functor then
      v.__functor v
    else
      throw "gen-schema: kind '${kind}' inherits '${parent}', whose kind value is not a module (its `mkType` result carries no `__functor`), so there is nothing to compose";

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
          # The collection is untyped, so either side may be any value: a string is quoted, anything
          # else is named by its type, as gen-graph's `renderId` does. Interpolating a non-string
          # would abort in the act of refusing.
          merge =
            acc: val:
            let
              show = v: if builtins.isString v then "'${v}'" else "<a ${builtins.typeOf v}>";
            in
            if acc != null && val != acc then
              throw "gen-schema: conflicting parent declarations: ${show acc} vs ${show val}"
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

  # gen-merge's structural-classification set, READ off its own published `moduleSyntax` record
  # (`lib/default.nix` there) rather than restated: RESTATING it was the defect (den-hoag-4kh.53.55
  # — an owning library publishes what it enforces; a consumer's second spelling drifts). Measured
  # at s7826 (den-hoag-1n12c): the old restated five-marker copy fell out of step with gen-merge's
  # own reader within one landing, refusing keys gen-merge reads. `moduleSyntax` is data only (a
  # plain-string-list record, ADR-0014), and it IS the set `configOf` enforces with, by construction
  # on gen-merge's side — never a narrower or stale spelling of it.
  #
  # Published as `schema._declarationKeys` — ONE derivation read by the guard and by the option,
  # never two spellings of one contract. It is a LIST because the enforced finite part of the
  # contract IS a finite list; the prefix rule and the option-declaration rule are NOT lists and go
  # in the option's description instead.
  declarationKeys = prelude.sort (a: b: a < b) merge.moduleSyntax.structured;

  # gen-merge reads the key comparison (`__keyEq`) a keyed kind module publishes only where its own
  # published key list carries it. Over a gen-merge without it the field is read as config, and
  # every kind that composes a parent would be refused as an undeclared option, so the pairing is
  # refused by name instead, once, where the key is written.
  mergeReadsKeyEq = builtins.elem "__keyEq" merge.moduleSyntax.structured;

  # The key comparison a keyed kind module publishes (`__keyEq.decide`). The DECISION is
  # `sealedCollisionEq`'s, the one `kindEq` and the ancestor map make; only the refusal is worded
  # here. Two instances sharing a key share a mark, so a refusal means their sealed subjects are
  # unequal, and one construction compared with itself is not: they are two separate constructions.
  # A sealed component is compared by its seal, the whole value under `==` (ADR-0034), where two
  # separately built functions are never equal, so they are refused even where the values they
  # compute are equal, and the text says so rather than that their values differ. Each component named is decided by the
  # same comparison over a one-key slice (`intersectAttrs` keeps the slot, as `sealedCollisionEq`'s
  # own slice does). Reached only on a dropped duplicate.
  keyDecide =
    kind: a: b:
    let
      site = "gen-schema: kind '${kind}' is imported twice under one key";
      same =
        x: y:
        let
          t = builtins.tryEval (sealedCollisionEq site x y);
        in
        t.success && t.value;
      r = builtins.tryEval (sealedCollisionEq site a b);
      slice = k: v: v // { sealed = builtins.intersectAttrs { ${k} = null; } v.sealed; };
    in
    if r.success then
      r.value
    else
      throw "${site}, as two separate constructions of one declaration: they mint one identity, and a sealed component is compared by its seal, the whole value under Nix `==`, where two separately built functions are never equal, so two constructions differ there even where the values they compute are equal. The component(s) whose seals differ: ${
        builtins.concatStringsSep ", " (
          map (k: "'${k}'") (
            builtins.filter (k: !(same (slice k a) (slice k b))) (builtins.attrNames a.sealed)
          )
        )
      }. Import one construction of '${kind}' in both places, or declare the two differently so that they mint two identities.";

  # ★ THE NAMES `mkSchemaEntryType` WRITES ONTO THE KIND VALUE, each with the writer that earns
  # it. RESTATED because this is gen-schema's OWN contract, not gen-merge's: the record is built
  # inside the merge body while `mkAllCollections` runs outside it, so it cannot be read off the
  # result. A name omitted here is an UNDER-fire — a missed refusal, never a false one — and the
  # §3b census is what keeps it from drifting.
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
    # Written beside `__mint`, both branches, for the same reason: the parents and the witness the
    # inheritance-cycle walk reads.
    "__kindImports"
    "__kindWitness"
    # Written beside them, both branches, for the same reason: the transitive ancestor map, and the
    # parents as written, which the cycle walk reads.
    "__kindAncestors"
    "__kindCycleParents"
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
  # and the caller's remedy is the same for all — rename the collection. A maintainer reads the
  # reason here, at the site they would edit.
  #
  # `schemaEntryFormals` joins the set for the construction-formal door's sake (den-hoag-q17cc,
  # below at `formalNamed`): a collection named `computed` would make that top-level key read as a
  # collection, and the ambiguity the door closes would reopen for exactly that name.
  #
  # ★ UNIFORM ACROSS BOTH BRANCHES, at a stated cost. On the `mkType` branch `finalCollections` is
  # never splatted into the result, so `mixins`, `refs` and `refinements` are inert there and
  # refusing them over-fires by three names. `reservedDeclarationKeysFor` branches on `mkType`
  # because `__functor` is LEGITIMATE on that branch; none of these three is legitimate as a
  # collection on either, so one list is taken over two.
  # `moduleSyntax.shorthandMeta` joins the module-key half of the reserved set beside
  # `declarationKeys` for collision case (A) above: gen-merge reads `require` as module syntax on a
  # SHORTHAND declaration (it joins `imports`), so a collection named `require` would delete
  # `imports` before the merge, silently, the same way a collection named for a structured key
  # already does. `declarationKeys` alone (gen-merge's STRUCTURED set) does not cover it, because a
  # shorthand-only key is never a structured one.
  reservedCollectionKeys = prelude.sort (a: b: a < b) (
    prelude.unique (
      declarationKeys ++ merge.moduleSyntax.shorthandMeta ++ kindResultKeys ++ schemaEntryFormals
    )
  );

  # ★ THE NAMES WITH A KIND-LEVEL READING THAT A KIND ENTRY'S TOP LEVEL MUST NOT CARRY
  # (den-hoag-q17cc). A kind entry is a module, and on the shorthand reading its top-level keys are
  # config for EVERY instance of the kind. Two families of names share that key position and mean
  # something at the KIND level instead, so a write there is misread silently: it lands on the
  # instances, and the kind value reads back its own value at the path just written.
  #
  #   · `schemaEntryFormals`: the names a schema is BUILT from. A construction formal is fixed by
  #     the call that builds the schema option, before the tree evaluates; `keySemantics` is
  #     extensible by ruling, never by accretion (ADR-0027), so reading the write AS the formal is
  #     not the remedy.
  #   · `publishedEntryKeys`, below: the rest of what this library WRITES onto the kind value,
  #     read off `kindResultKeys` — less the module keys gen-merge reads (`options`) and the
  #     `_`-prefixed names `reservedDeclarationKeysFor` already refuses — so a name added there is
  #     reserved here with no second edit.
  #
  # Refusing is the construction (ADR-0025 item 1): the misreading becomes inexpressible on a
  # DIRECT entry def, here. A module the entry IMPORTS is reached by `entryReservation` below, at
  # gen-merge's collector, which alone sees an imported module's top level after function modules
  # are applied and `imports` flattened. The two doors partition the routes, so each write meets
  # one. An instance field of such a name is untouched: it is written on the instance, or under
  # `config.` on the entry, where the instance reading is explicit.
  publishedEntryKeys = builtins.filter (
    k:
    !(prelude.hasPrefix "_" k)
    && !(builtins.elem k declarationKeys)
    && !(builtins.elem k schemaEntryFormals)
  ) kindResultKeys;

  # ★ THE SAME NAMES, IN A MODULE THE KIND ENTRY IMPORTS (den-hoag-8x97u). The direct-def door above
  # reads the entry's own top level; a reserved name one `imports` (or `require`, or function
  # module, or path) away is read as instance config by gen-merge's collector, which flattens the
  # closure. gen-merge enforces a reservation over a marked module's import closure
  # (`__reservedKeys`) and names no kind or formal, so this library supplies the content as plain
  # data: each reserved name with its refusal text, and the kind shape the cxlc0 `inherits` alias
  # reads (`schemaKindShape`), which is exempt so a kind value in `imports` stays an inheritance.
  # The default branch marks the defs `merged` imports; gen-aspects marks its own `defsModules`
  # with this set and its `cnfKeys` (exported for that). A custom `mkType` that builds instance
  # modules from `defs` applies it the same way, or that route is outside the door.
  entryReservation = kind: {
    exempt = schemaKindShape;
    names = builtins.listToAttrs (
      map (f: {
        name = f;
        value = "gen-schema: kind '${kind}': declaration key '${f}' is a construction formal of this schema, written in a module this kind entry imports — it is fixed by the call that builds the schema option (`mkSchemaOption`, `mkSchemaEntryType`), and written there it is not read as one; pass '${f}' to that constructor, or write `config.${f}` for an instance field of that name, which a strict instance must declare as an option";
      }) schemaEntryFormals
      ++ map (f: {
        name = f;
        value = "gen-schema: kind '${kind}': declaration key '${f}' is a name gen-schema writes onto the kind value, written in a module this kind entry imports — there it lands on every instance, while reading `config.schema.${kind}.${f}` returns the published one; write `config.${f}` for an instance field of that name, which a strict instance must declare as an option";
      }) publishedEntryKeys
    );
  };

  isStructuredDecl =
    v: builtins.isAttrs v && prelude.any (k: v ? ${k}) merge.moduleSyntax.structuring;

  # ★ THE NAMES THIS LIBRARY WRITES ONTO THE KIND VALUE ITSELF. They begin with `_`, so the prefix
  # rule would admit them as "consumer-private metadata gen-schema must not read" — and they are the
  # opposite of that. The population is READ OFF the merge result's own key set, not assumed:
  # `[ __functor __mint ]` on the default branch and `[ __mint ]` on the `mkType` branch, since that
  # branch declares no `__functor`. Measured at `1ce3eef`: a declared `__mint` does not survive and
  # the kind's own mark is byte-identical with and without it; a declared `__functor` is applied by
  # gen-merge's module classifier and DELETES the rest of the declaration (`options` ⇒ `[ ]` against
  # `[ "role" ]` on the clean twin). Same class, same strength and same shape as the three reserved
  # COLLECTION keys `mkAllCollections` refuses above. `__kindImports` and `__kindWitness` are written on
  # both branches too (the inheritance-cycle walk's parents and witness), and a shorthand declaration of
  # either was discarded without a word, a declared parent with it; `__kindAncestors` (the ancestor
  # map) and `__kindCycleParents` (the parents as written) are written beside them. All four are
  # `_`-prefixed, so `publishedEntryKeys` leaves them to this door.
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
        "__keyEq"
        "__kindAncestors"
        "__kindCycleParents"
        "__kindImports"
        "__kindWitness"
        "__mint"
        "__sealed"
      ]
    else
      [
        "__keyEq"
        "__kindAncestors"
        "__kindCycleParents"
        "__kindImports"
        "__kindWitness"
        "__mint"
        "__sealed"
      ];

  # A top-level option declaration is never a read plane once the declaration asserts ANY
  # module-syntax vocabulary: a kind entry is a module, and neither gen-merge nor nixpkgs collects a
  # top-level `mkOption` as a declaration (den-hoag-zijk1). INDEPENDENT of `isStructuredDecl` on
  # purpose (Arm 1, den-hoag-declaration-markers-restated-1n12c): `moduleSyntax.structuring` narrowed
  # to `config`/`options` only reclassifies an `imports`-only or `freeformType`-only decl as
  # SHORTHAND, which would otherwise stand the whole guard down and admit a flat `mkOption` record as
  # ordinary config — silently dropping zijk1's guarantee for exactly that case. Reuses
  # `isOptionDecl`, the same predicate `optionsOf`/`extractedRefinements` read, rather than a second
  # one.
  #
  # GATED on `moduleSyntax.structured` — gen-merge's full published key list, not the narrowed
  # `structuring` pair — never unconditional: a decl asserting NO module-syntax key at all (none of
  # `imports`, `freeformType`, `config`, `options`, `key`, `meta`, …) is data through and through, and
  # gen-merge's `configOf` reads it as ordinary config with no ambiguity; an option-shaped VALUE there
  # is then no different from any other value a config key may hold. The ambiguity zijk1 names only
  # arises once the decl also asserts some module-syntax key — that is where a reader could mistake
  # the flat option for a declaration instead of a value. An earlier, unconditional pass regressed two
  # live cells that depend on exactly this admission
  # (`kind-mixins.test-entry-type-empty-mixins-default`,
  # `reverse-half-read.test-flat-unstructured-lands-no-refinement`), driven and read, not asserted.
  carriesModuleSyntaxKey =
    v: builtins.isAttrs v && prelude.any (k: v ? ${k}) merge.moduleSyntax.structured;

  flatOptionValuedKeys =
    v:
    if builtins.isAttrs v && carriesModuleSyntaxKey v then
      builtins.filter (k: isOptionDecl v.${k}) (prelude.attrNames v)
    else
      [ ];

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
    # CLAUSE B · on an UNSTRUCTURED def gen-merge's `configOf` reads EVERY OTHER key as config, so
    # only `flatOptionValuedKeys` is unread here — the one plane no regime ever gives a flat
    # `mkOption` record to.
    else if !(isStructuredDecl v) then
      flatOptionValuedKeys v
    else
      # Scoped to the kind entry: a mixin `baseModule` is a RECORD, and `bridge.nix`'s `emitModule`
      # is the typed record→module boundary that lifts its flat option records soundly.
      prelude.unique (
        flatOptionValuedKeys v
        ++ builtins.filter (
          k:
          # RULE 4 · any key beginning with `_` is consumer-private metadata this library must not
          # read. A PREFIX rule, not a list: it admits every present and future `_`-prefixed module
          # metadata key gen-merge adds, and gen-schema already enforces `_` as its reserved prefix
          # one plane up (`reservedKindNames`, below). The reserved names above are its one exception
          # and are refused by their own door, before this predicate runs.
          !(prelude.hasPrefix "_" k)
          # RULES 1-3 · this schema's collection keys (reader: `extractedCollections`) and gen-merge's
          # published structured-module keys, `merge.moduleSyntax.structured` (readers: `configOf`,
          # `optionsOf`, `importsOf`, `topFreeformOf`), which already includes `key`.
          && !(builtins.elem k (declarationKeys ++ collectionKeys))
        ) (prelude.attrNames v)
      );

  # Names EVERY offending key on the first offending def, never just the first — a three-typo
  # migration is otherwise three round trips. The recognised sets are RENDERED FROM the bindings the
  # predicate reads, never restated as literals in the string, so they cannot drift out of step.
  unknownDeclarationKeyRefusal =
    kind: collectionKeys: unknown: structured: file:
    let
      noun = if builtins.length unknown == 1 then "key" else "keys";
      named = builtins.concatStringsSep ", " (map (k: "'${k}'") unknown);
      first = builtins.head unknown;
    in
    "gen-schema: kind '${kind}': unrecognised declaration ${noun} ${named} (declared in ${file}). "
    + (
      if structured then
        "This declaration is structured — it carries `config` or `options` — so gen-schema reads only: "
        + "this schema's collection keys "
        + "[${builtins.concatStringsSep ", " collectionKeys}] (published as `schema._collectionKeys`), "
        + "the module keys [${builtins.concatStringsSep ", " declarationKeys}] "
        + "(published as `schema._declarationKeys`), and any `_`-prefixed key. Every other key is "
        + "discarded unread. "
      else
        "This declaration is config shorthand, so gen-schema reads every other key as config; a flat "
        + "option declaration alone is never a read plane here, structured or not. "
    )
    + "Declare '${first}': `options.${first} = mkOption { … };` for an option, "
    + "`config.${first} = …` for a value on an option already declared, `_${first}` for "
    + "consumer-private metadata gen-schema must not read, or `${first}` as a collection on "
    + "mkSchemaOption for schema-level data.";

  # THE ACCEPTED SET FOR BOTH DOORS BELOW — ONE LIST, NOT TWO REFLECTIONS OF IT (P1, den-hoag-7gp66).
  # Before P1 the two doors carried native attrset formals and `mkSchemaOption` asked
  # `builtins.functionArgs` whether the two sets agreed at runtime; `functionArgs` reflects only a
  # native attrset-pattern lambda, and a P1 door is a bare positional `args:` lambda, so that
  # reflection would read `{}` for both and the invariant it existed to state ("the option's type is
  # its entry type's construction", den-hoag-px98p) would hold vacuously rather than meaningfully.
  # This list is what each door's own `checkOptions` closes over AND what `mkSchemaEntryType`'s own
  # `components` self-check compares itself against below, so the invariant is true by construction
  # — one list, read twice — and `mkSchemaOption` calls `mkSchemaEntryType` unconditionally rather
  # than behind a runtime `==` of two reflections.
  schemaEntryFormals = [
    "baseModule"
    "collections"
    "computed"
    "mixins"
    "mkType"
    "strict"
    "keySemantics"
    "specialArgs"
  ];

  # OPTIONS door (P1): every formal is optional, so `checkOptions` alone closes it. The `assert`
  # forces `checked` where the record is applied — the door's own return is built through
  # `merge.mkOptionType`, an external call whose own strictness this door does not want to depend
  # on for its catchability.
  mkSchemaEntryType = mkSchemaEntryTypeIn null;

  # THE ENTRY TYPE OF ONE KIND TREE (den-hoag-8c8pr, owner-ruled 2026-09-30: `inherits` on a tree
  # `evalSchema` did not build means what `imports = [ config.schema.<p> ]` means there). `tree` is
  # the tree's own `config` — the kind values the deprecated spelling reads — or `null` for an entry
  # type built outside a tree, where a declared parent has nothing to be read from.
  mkSchemaEntryTypeIn =
    tree: args:
    let
      checked = prelude.checkOptions "gen-schema.mkSchemaEntryType" schemaEntryFormals args;
    in
    # `checked` is applied to a NATIVE attrset-pattern lambda rather than destructured field-by-field
    # above: each field below becomes a `compared` component (see `components`, below) whose value
    # `constructionRelation` must keep the SLOT this constructor was HANDED, not a fresh selection off
    # it — upstream Nix `==` keeps a function's identity only for the one slot it was bound to, and a
    # `let`-bound selection (`checked.computed or null`) allocates a fresh one per construction, so two
    # calls sharing one `computed` would be refused (den-hoag-jzatq). A native formal, applied to
    # `checked` (== `args`, unchanged by a successful `checkOptions`), binds the identical slot the
    # pre-P1 door bound directly, so the door catches an unknown option (R6, above) without giving up
    # the identity `constructionRelation` depends on.
    (
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

        # ONE introspection for both arms: the option tree an instance imports and its refs, from
        # one `evalModuleTree` over the module an instance imports. Each arm
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
            # `schemaEntryFormals` (above), not `builtins.functionArgs mkSchemaEntryType`: reflection
            # over a bare positional `args:` lambda answers `{}` (P1, den-hoag-7gp66), which would
            # make this check vacuously true rather than a live comparison against the door's accepted
            # set.
            formals = prelude.sort (a: b: a < b) schemaEntryFormals;
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
                if name == "inherits" then aliasedInherits declaredRendered else declaredOf name collection
              ) allCollections;

              declaredOf =
                name: collection:
                prelude.foldl' (
                  acc: d:
                  if builtins.isAttrs d.value && d.value ? ${name} then
                    inferMerge name collection acc d.value.${name}
                  else
                    acc
                ) collection.default defs;

              # A DECLARED parent nothing else composes (den-hoag-8c8pr), which the desugar below
              # imports: no def of this kind carries the resolver's provenance for it, and it is not
              # spelled either (a spelled parent composes where it is written). Computed only past a
              # non-empty declaration, so a kind that inherits nothing pays one comparison.
              # `inherits` holds names and kind VALUES (den-hoag-l0y F4). A value is the tree's own iff
              # the tree holds an entry at its name with an equal mark and `kindEq` decides `true` (an
              # equal mark `kindEq` refuses is that refusal), and then it IS the name; anything else,
              # and every value off a tree, is foreign and stays a VALUE entry, never resolved against
              # an in-tree name (ADR-0034: identity through the one mint, never by name). It forces
              # both marks where `inherits` is read, so the cycle walk reads `cycleParents` instead.
              formOf =
                v:
                if !(isSchemaKind v) then
                  throw "gen-schema: kind '${kind}' inherits ${
                    if builtins.isAttrs v then "an attrset with no mark" else "a ${builtins.typeOf v}"
                  }: an `inherits` entry is a kind name or a kind value (`kind` and a mint-backed mark `__mint.minted`)"
                else if
                  tree != null
                  && builtins.elem v.kind tree._kindNames
                  && tree.${v.kind}.__mint.minted == v.__mint.minted
                  && kindEq tree.${v.kind} v
                then
                  "name"
                else
                  "value";
              rendered = v: if builtins.isString v || formOf v == "value" then v else v.kind;
              declaredRaw = declaredOf "inherits" allCollections.inherits;
              declaredRendered = map rendered declaredRaw;
              declaredInherits = builtins.filter builtins.isString declaredRendered;
              declaredValues = builtins.filter (v: !(builtins.isString v)) declaredRendered;
              # the spelled parents that are the tree's own, by name: a foreign spelled value is not
              # the same-named declared parent and does not stand in for it
              spelledNames = map (k: k.kind) (builtins.filter (k: formOf k == "name") kindImports);
              unresolvedInherits =
                if declaredInherits == [ ] then
                  [ ]
                else
                  let
                    files = map (d: d.file or null) defs;
                    spelled = spelledNames;
                  in
                  builtins.filter (
                    p: !(builtins.elem (inheritsResolvedFile kind p) files) && !(builtins.elem p spelled)
                  ) declaredInherits;
              # Sited on the COMPOSED value (`merged`, `treeModule`), never the kind's WHNF: `evalSchema`
              # reads `inherits` off pass 0, where no parent is resolved yet, and the collections, `kind`
              # and `_kindNames` stay readable. It carries two refusals, each at every read that would
              # compose the parent: `options`, `refs` (so `_edges`), the mark, an instance. An
              # inheritance cycle, in either spelling, on any tree; and a declared parent on an entry
              # type built outside a tree, which has no parent to read.
              # A computed field is caller-built from the raw defs as well, so it is read through the
              # guard on both branches, as the `mkType` result's own fields are.
              guardedComputed = prelude.mapAttrs (_: resolvedOnly) computedFields;
              resolvedOnly =
                v:
                if inheritanceCycle != null then
                  throw "gen-schema: inheritance cycle among kinds [${
                    prelude.concatStringsSep " " (
                      prelude.sort (a: b: a < b) (prelude.unique (prelude.init inheritanceCycle))
                    )
                  }] — kind '${kind}' inherits itself through its parents (${prelude.concatStringsSep " -> " inheritanceCycle}); a kind may inherit only kinds resolved in a strictly earlier pass"
                else if unresolvedInherits != [ ] && tree == null then
                  throw "gen-schema: kind '${kind}' inherits '${builtins.head unresolvedInherits}', but nothing resolved it: this entry type was built outside a kind tree, so there is no parent to read. Declare the kind through `mkSchemaOption` or `evalSchema`"
                else
                  builtins.seq lineageChecked v;

              # THE LINEAGE REFUSALS, after the cycle walk (the fold forces marks, which a cycle would
              # recurse through): the ancestor map's diamond refusal and the class check. Read through
              # `resolvedOnly`, so at the composed reads only; a kind with no parents pays one comparison.
              lineageChecked =
                if kindParents == [ ] then
                  true
                else if builtins.seq kindAncestors classDefects == [ ] then
                  true
                else
                  let
                    d = builtins.head classDefects;
                    show = c: if builtins.isString c then "'${c}'" else "<a ${builtins.typeOf c}>";
                  in
                  throw (
                    "gen-schema: kind '${kind}' inherits '${d.ancestor}', whose keySemantics "
                    + (
                      if d.own then
                        "gives the key '${d.key}' the category ${show d.theirs}, and this kind's keySemantics gives it ${show d.ours}"
                      else
                        "declares the key '${d.key}', and this kind's keySemantics does not"
                    )
                    + ": a subkind's keySemantics must hold every key of each ancestor's, with the same category; build this kind's schema with '${d.key}' in its keySemantics as the ancestor declares it"
                  );

              # THE TRANSITIVE ANCESTOR MAP (den-hoag-l0y): mark -> ancestor kind VALUE, read per kind
              # value and never memoised by mark, so nodes share one reference per kind. A fold over the
              # ancestor DAG, linear in the ancestors reached: a mark already present is decided through
              # `sealedCollisionEq`, the decision `kindEq` makes, with a site naming this kind and both
              # lineage paths. Equal marks decide `true` (a diamond over one kind: one entry, not walked
              # again) or refuse by name, so two declarations of one identity reached along two paths are
              # never merged last-wins. Distinct marks are two kinds, and composing both is gen-merge's to
              # refuse where they conflict. A kind value this entry type did not build publishes no
              # parents, so the walk stops at it. Published as `__kindAncestors`.
              kindAncestors =
                let
                  arrow = prelude.concatStringsSep " -> ";
                  subjectOf = p: {
                    name = p.kind;
                    mark = p.__mint.minted;
                    sealed = p.__sealed or null;
                  };
                  step =
                    path: acc: p:
                    let
                      m = p.__mint.minted;
                      here = path ++ [ p.kind ];
                    in
                    if acc ? ${m} then
                      builtins.seq (sealedCollisionEq
                        "gen-schema: kind '${kind}' reaches '${p.kind}' along ${arrow acc.${m}.path} and along ${arrow here}"
                        (subjectOf acc.${m}.value)
                        (subjectOf p)
                      ) acc
                    else
                      builtins.foldl' (step here) (
                        acc
                        // {
                          ${m} = {
                            value = p;
                            path = here;
                          };
                        }
                      ) (p.__kindImports or [ ]);
                in
                prelude.mapAttrs (_: e: e.value) (builtins.foldl' (step [ kind ]) { } kindParents);

              # THE CLASS RULE IS A CHECK (den-hoag-l0y C2): `keySemantics` is a construction formal,
              # fixed before the tree resolves `inherits`, so a subkind cannot take a union of its
              # ancestors' — that would make the formal read the tree it constructs. Each ancestor's key
              # must be present with the same `category`; categories are compared as values, never
              # interpreted (the vocabulary is the consumer's).
              classDefects =
                let
                  catOf = e: if builtins.isAttrs e then e.category or null else null;
                in
                prelude.concatMap (
                  a:
                  let
                    theirs = a.keySemantics or { };
                  in
                  prelude.concatMap (
                    k:
                    if !(keySemantics ? ${k}) then
                      [
                        {
                          ancestor = a.kind;
                          key = k;
                          own = false;
                        }
                      ]
                    else if catOf keySemantics.${k} != catOf theirs.${k} then
                      [
                        {
                          ancestor = a.kind;
                          key = k;
                          own = true;
                          ours = catOf keySemantics.${k};
                          theirs = catOf theirs.${k};
                        }
                      ]
                    else
                      [ ]
                  ) (prelude.attrNames theirs)
                ) (builtins.attrValues kindAncestors);

              # THE PARENTS THIS KIND COMPOSES, as kind VALUES, in either spelling: the spelled ones
              # (`kindImports`) and, on a tree, each declared name the tree holds and nothing spelled.
              # Both compose through the same applied functor, so one list carries both to the cycle
              # walk and the ancestor map. A declared parent is published as `tree.${p}`, the value a
              # caller reads off the tree, whether the desugar or `evalSchema` composed it: the parent
              # `evalSchema` composed is its pass n-1 twin, which `kindEq` refuses against the value read
              # whenever an option carries a default. Published as `__kindImports`.
              kindParents =
                kindImports
                ++ declaredValues
                ++ (
                  if tree == null then
                    [ ]
                  else
                    map (p: tree.${p}) (
                      builtins.filter (
                        p: builtins.elem p tree._kindNames && !(builtins.elem p spelledNames)
                      ) declaredInherits
                    )
                );

              # THE PARENTS AS WRITTEN, before `formOf` decides any of them: the spelled values, the
              # declared values and the declared names the tree holds. Read by the witness and by the
              # cycle walk of every kind, which run before composition and so force no mark: a cycle
              # through a same-tree VALUE entry would otherwise need each partner's mark to classify
              # it, and recurse uncatchably. Published as `__kindCycleParents`.
              cycleParents =
                kindImports
                ++ builtins.filter isSchemaKind declaredRaw
                ++ (
                  if tree == null then
                    [ ]
                  else
                    map (p: tree.${p}) (
                      builtins.filter (p: builtins.isString p && builtins.elem p tree._kindNames) declaredRaw
                    )
                );

              # THE CONTENT WITNESS: the kind's name, each def's file and first-attribute position, its
              # parents' names and its declared option names, read before composition. Its one reader
              # is the inheritance-cycle walk, which runs before composition and so cannot read a mark;
              # the module key is the mark (below). Published as `__kindWitness`.
              kindWitness = builtins.hashString "sha256" (
                builtins.unsafeDiscardStringContext "${kind}@${
                  prelude.concatStringsSep ";" (map (d: "${toString (d.file or "?")}=${witnessPos d.value}") defs)
                }|parents=${prelude.concatStringsSep "," (map (k: k.kind) cycleParents)}|opts=${
                  prelude.concatStringsSep "," (
                    prelude.concatMap (
                      d:
                      if builtins.isAttrs d.value && builtins.isAttrs (d.value.options or null) then
                        builtins.attrNames d.value.options
                      else
                        [ ]
                    ) defs
                  )
                }"
              );

              # THE ONE INHERITANCE-CYCLE WALK (8c8pr Q-b arm (i), 2026-09-30), for both spellings: a
              # kind that reaches its own witness through its parents' `__kindCycleParents` would import
              # itself into itself, and the module system recurses uncatchably. It is refused by name,
              # in `evalSchema`'s wording, because a kind may inherit only kinds resolved in a strictly
              # earlier pass (ADR-0016 ruling 7). A parent reached twice is a diamond, not a cycle: the
              # visited set is keyed by witness, so the walk is linear in the parents reached. Compared
              # by witness, never by name, so another tree's same-named kind is not this one. The
              # answer is the path, first member to its return, or `null`. The refusal names the members
              # sorted, as `evalSchema`'s `kindNames` order does, so its bracket does not depend on which
              # member is read; the path is in walk order from the kind read.
              # ponytail: each kind walks its own ancestry (nothing is shared across kinds, since a
              # shared reach set would itself recurse on a cycle) and copies the path per step, so a
              # depth-n chain costs O(n²) in total, the same order as composing it; carry the path as
              # a cons list if a deep spelling-heavy tree ever makes that dominate.
              inheritanceCycle =
                let
                  go =
                    acc: stack: v:
                    let
                      w = v.__kindWitness;
                    in
                    # A kind value this entry type did not build (`isSchemaKind` admits any value with a
                    # `kind` and a mark) publishes no parents, so the walk has nothing past it to read.
                    if acc.found != null || !(v ? __kindCycleParents) then
                      acc
                    else if w == kindWitness then
                      acc // { found = stack ++ [ v.kind ]; }
                    else if acc.seen ? ${w} then
                      acc
                    else
                      builtins.foldl' (a: go a (stack ++ [ v.kind ])) (
                        acc
                        // {
                          seen = acc.seen // {
                            ${w} = true;
                          };
                        }
                      ) v.__kindCycleParents;
                in
                if cycleParents == [ ] then
                  null
                else
                  (builtins.foldl' (a: go a [ kind ]) {
                    found = null;
                    seen = { };
                  } cycleParents).found;

              # THE DESUGAR (den-hoag-8c8pr): on a tree, a declared parent nothing else composed is
              # imported into this kind exactly as the deprecated spelling `imports = [ config.schema.<p> ]`
              # imports it, read off the same tree. The def is the one `evalSchema`'s pass contributes
              # (`inheritedModule`), so a staged and an unstaged tree compose one module; no name graph,
              # no pass: the module system's import composes it, as it composes the spelling.
              # A foreign VALUE entry composes as itself, through the same applied functor, on any tree
              # or none: it is already minted, so nothing resolves it.
              desugaredDefs =
                map (v: {
                  file = "<gen-schema: kind '${kind}' inherits the kind value '${v.kind}'>";
                  value.imports = [ (inheritedModule kind v.kind v) ];
                }) declaredValues
                ++ (
                  if tree == null then
                    [ ]
                  else
                    map (p: {
                      file = inheritsDesugaredFile kind p;
                      value = {
                        imports = [
                          (
                            if !(builtins.elem p tree._kindNames) then
                              throw "gen-schema: kind '${kind}' inherits '${p}' which is not a declared kind"
                            else
                              inheritedModule kind p tree.${p}
                          )
                        ];
                      };
                    }) unresolvedInherits
                );

              # THE DEPRECATED INHERITANCE SPELLING, READ AS `inherits` (den-hoag-cxlc0): each kind
              # value the walk below finds in this entry's `imports`/`require` contributes the entry
              # `inherits = [ <value> ]` would (den-hoag-l0y K1): through `formOf`, its NAME if it is
              # the tree's own and the VALUE if it is foreign, after the declared parents, in walk
              # order, once, and never an entry already declared. The value still composes where it
              # was written: that is the parent's module, the same one `evalSchema`'s injection
              # composes for a declared `inherits`. The warning rides the `inherits` value, so it fires
              # where the entry is read: the collection itself, `_edges`, and every mark and
              # `id_hash`, whose preimage carries the collections.
              #
              # ★ NOT AT THE KIND'S WHNF. `formOf` forces each spelled value's mark, and so the other
              # kind's composition, where `inherits` is read. A CYCLE is therefore refused by the
              # cycle walk over `cycleParents` (above), which forces no mark, in the entry type's
              # wording — under `evalSchema` too, whose pass 0 reads `inherits` and so meets the
              # partner's own guard before its name graph does.
              aliasedInherits =
                declared:
                let
                  entryKey = e: if builtins.isString e then "n:${e}" else "m:${e.__mint.minted}";
                  spelled =
                    (builtins.foldl'
                      (
                        acc: e:
                        if acc.seen ? ${entryKey e} then
                          acc
                        else
                          {
                            seen = acc.seen // {
                              ${entryKey e} = true;
                            };
                            out = acc.out ++ [ e ];
                          }
                      )
                      {
                        seen = { };
                        out = [ ];
                      }
                      (map rendered kindImports)
                    ).out;
                  declaredKeys = map entryKey declared;
                  names = builtins.filter (e: !(builtins.elem (entryKey e) declaredKeys)) spelled;
                  quoted = prelude.concatStringsSep " " (prelude.unique (map (k: "'${k.kind}'") kindImports));
                  literal = prelude.concatStringsSep " " (
                    map (e: if builtins.isString e then "\"${e}\"" else "<the kind value '${e.kind}'>") spelled
                  );
                in
                if kindImports == [ ] then
                  declared
                else
                  warn
                    "gen-schema: kind '${kind}': its `imports` carries the kind value ${quoted}, the deprecated spelling of kind inheritance, read as `inherits = [ ${literal} ]`; declare `inherits`"
                    (declared ++ names);

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

              # Strip all collection keys before deferredModule merge. The desugared parents join here,
              # where `evalSchema`'s injected defs arrive, so both branches compose them.
              strippedDefs =
                map (
                  d:
                  if builtins.isAttrs d.value && prelude.any (k: d.value ? ${k}) collectionKeys then
                    d // { value = builtins.removeAttrs d.value collectionKeys; }
                  else
                    d
                ) defs
                ++ desugaredDefs;

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
              # `mkType` branch no input is ever named. What is live on both branches is the
              # construction-formal door and the reserved door below, because the formals and
              # `__mint` belong to both.
              #
              # Forcing the result to WHNF forces the conditional, which is what makes a `builtins.seq`
              # unnecessary. The guard is sited HERE, in the descriptor's own `merge` body, rather than
              # on a completed type: gen-merge's `mkOptionType` maps a foreign descriptor's `merge` onto
              # the internal `mergeDefs` and every container dispatches on that, so a `t // { merge = …; }`
              # override is silently ignored.
              topKeysIn =
                names:
                prelude.concatMap (
                  d: if builtins.isAttrs d.value then builtins.filter (k: d.value ? ${k}) names else [ ]
                ) defs;
              reservedNamed = topKeysIn (reservedDeclarationKeysFor mkType);
              # The construction-formal door (den-hoag-q17cc, at `publishedEntryKeys`). Same site and
              # same per-def test as `reservedNamed`, so it is live on both branches; it runs FIRST,
              # so a structured def gets the formal's text and not the surplus clause's "declare an
              # option" remedy, which points at the wrong surface.
              formalNamed = topKeysIn schemaEntryFormals;
              publishedNamed = topKeysIn publishedEntryKeys;

              # THE DEPRECATED INHERITANCE SPELLING (den-hoag-cxlc0), found for `aliasedInherits`
              # above: a kind VALUE in a kind entry's `imports` (or a shorthand def's `require`), found
              # by the walk `modulesOf` makes for the plane. Inheritance travels as a NAME in
              # `inherits`, resolved by `evalSchema`, which imports the parent's applied functor rather
              # than its kind value. A VALUE test: a path or string member is imported, which needs no
              # argument and yields the value gen-merge would compose, and an imported attrset module
              # is walked in turn, so a kind reached through files is read too. Each file is imported
              # once per kind entry (a visited set keyed by the resolved path, as the module system
              # dedupes), so a cycle of files terminates. It applies no function, so a function module
              # and a hand-applied functor compose unaliased and unwarned — the README's declared
              # ADR-0025 exception. What it forces, where `inherits` is read: every `imports` and
              # `require` list of every attrset module reachable from the defs, every member of those
              # lists, the `__mint` record of any member carrying `kind` and `__mint`, and the import
              # of every reachable path or string member. The module system imports those files
              # anyway; what moves is when.
              declListOf =
                v:
                let
                  i = v.imports or [ ];
                in
                (if v ? require && !(isStructuredDecl v) then v.require else [ ])
                ++ (if builtins.isList i then i else [ i ]);
              # ponytail: `found ++ [ … ]` is quadratic in the members reached; a kind entry's module
              # tree is small. Accumulate a list of lists if that stops being true.
              walkKindMembers =
                acc: xs:
                builtins.foldl' (
                  acc: m:
                  if m ? opaque && (builtins.isPath m.opaque || builtins.isString m.opaque) then
                    let
                      # the path as an attribute name: a store path carries string context, which a name cannot
                      key = builtins.unsafeDiscardStringContext (toString m.opaque);
                      v = import m.opaque;
                      acc' = acc // {
                        seen = acc.seen // {
                          ${key} = true;
                        };
                        found = acc.found ++ [ v ];
                      };
                    in
                    if acc.seen ? ${key} then
                      acc
                    else if builtins.isAttrs v && !(v ? __functor) then
                      walkKindMembers acc' (declListOf v)
                    else
                      acc'
                  else
                    acc // { found = acc.found ++ [ (m.open or m.opaque) ]; }
                ) acc (modulesOf xs);
              kindImports =
                builtins.filter isSchemaKind
                  (builtins.foldl'
                    (
                      acc: d:
                      if builtins.isAttrs d.value && !(d.value ? __functor) then
                        walkKindMembers acc (declListOf d.value)
                      else
                        acc
                    )
                    {
                      seen = { };
                      found = [ ];
                    }
                    defs
                  ).found;

              surplusOffenders = builtins.filter (
                d: surplusDeclarationKeys { inherit computed mkType; } collectionKeys d.value != [ ]
              ) defs;

              checkDeclarationKeys =
                result:
                if formalNamed != [ ] then
                  throw "gen-schema: kind '${kind}': declaration key '${builtins.head formalNamed}' is a construction formal of this schema — it is fixed by the call that builds the schema option (`mkSchemaOption`, `mkSchemaEntryType`), and written on a kind entry it is not read as one; pass '${builtins.head formalNamed}' to that constructor, or write `config.${builtins.head formalNamed}` for an instance field of that name, which a strict instance must declare as an option"
                else if publishedNamed != [ ] then
                  throw "gen-schema: kind '${kind}': declaration key '${builtins.head publishedNamed}' is a name gen-schema writes onto the kind value — written on a kind entry it lands on every instance, while reading `config.schema.${kind}.${builtins.head publishedNamed}` returns the published one; write `config.${builtins.head publishedNamed}` for an instance field of that name, which a strict instance must declare as an option"
                else if reservedNamed != [ ] then
                  throw (
                    if builtins.head reservedNamed == "__keyEq" then
                      "gen-schema: kind '${kind}': declaration key '__keyEq' is reserved — gen-schema publishes the key comparison of every kind that composes a parent, beside the key it derives from the kind's mark, and a declaration does not choose it"
                    else
                      "gen-schema: kind '${kind}': declaration key '${builtins.head reservedNamed}' is reserved — gen-schema writes it onto every kind value and a declared one is discarded unread"
                  )
                else if surplusOffenders != [ ] then
                  let
                    offender = builtins.head surplusOffenders;
                  in
                  throw (
                    unknownDeclarationKeyRefusal kind collectionKeys (surplusDeclarationKeys {
                      inherit computed mkType;
                    } collectionKeys offender.value) (isStructuredDecl offender.value) (offender.file or "<unknown>")
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
                  treeModule = resolvedOnly (
                    {
                      _file = "<gen-schema mkType kind ${kind}>";
                    }
                    // custom
                    // published
                    // computedFields
                  );
                  introspect = introspectOf treeModule;
                  # ONE plane for the published fields, the mark and `kindEq` (c+): this arm's option
                  # plane is the tree an instance imports, so it enters the preimage.
                  plane = planeOf {
                    inherit (introspect) options refs;
                    collections = extractedCollections;
                    inherit keySemantics;
                    computed = computedFields;
                    modules = map (d: d.value) strippedDefs ++ [ resolvedBase ];
                    functions = { inherit mkType computed; };
                  };
                in
                # Every field the caller's `mkType` built is read THROUGH the guard (den-hoag-8c8pr): the
                # result is the caller's key space (`__defsModule`, or anything else built from `defs`),
                # which gen-schema cannot enumerate, so each value is guarded rather than each name.
                # Names stay lazy; a kind that inherits nothing pays one thunk per field.
                prelude.mapAttrs (_: resolvedOnly) custom
                # The two containment and inheritance relations are WRITTEN here, over the result,
                # because their readers take them off the kind value — `evalSchema` reads `inherits`,
                # `_topology` reads `parent` — and a result that publishes no collections would otherwise
                # lose a declared edge without a word (den-hoag-fwoa8). Unguarded: both are read on an
                # unresolved kind (`evalSchema`'s pass 0). Before the computed fields, which win over a
                # collection on both branches.
                // {
                  inherit (extractedCollections) inherits parent;
                }
                // published
                // {
                  inherit (introspect) options refs;
                  refinements = refinementsOfOptions introspect.options;
                }
                # The result's functor is applied to `treeModule`, so the tree and an instance hand it
                # the same `self` and a functor that reads `self.options` declares one plane in both.
                # Applied before the computed fields, which still win for same-named keys.
                // prelude.optionalAttrs (custom ? __functor) {
                  # Guarded over the APPLIED module, not only through `treeModule`: a functor that
                  # ignores its `self` never forces the tree module, and would compose unguarded.
                  __functor = _: resolvedOnly (custom.__functor treeModule);
                }
                // guardedComputed
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
                  __kindImports = kindParents;
                  __kindCycleParents = cycleParents;
                  __kindWitness = kindWitness;
                  __kindAncestors = resolvedOnly kindAncestors;
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

                  # The defs `merged` imports carry `entryReservation` (den-hoag-8x97u), so a
                  # reserved name in a module they import refuses at gen-merge's collector. The
                  # marker rides IN PLACE on a plain attrset def, which adds no collected entry; a
                  # function, functor or path def is wrapped, because an applied functor's result
                  # would drop an in-place key. The plane's `modules` stay the unmarked
                  # `strippedDefs`, so no kind's mark moves.
                  reservation = entryReservation kind;
                  merged = resolvedOnly (
                    base.merge loc (
                      map (
                        d:
                        d
                        // {
                          value =
                            if builtins.isAttrs d.value && !(d.value ? __functor) then
                              d.value // { __reservedKeys = reservation; }
                            else
                              {
                                __reservedKeys = reservation;
                                imports = [ d.value ];
                              };
                        }
                      ) strippedDefs
                      ++ injected
                    )
                  );

                  introspect = introspectOf merged;
                  plane = planeOf {
                    inherit (introspect) options refs;
                    collections = finalCollections;
                    inherit keySemantics;
                    computed = computedFields;
                    modules = map (d: d.value) strippedDefs ++ [ effectiveBase ];
                    functions = { inherit mkType computed; };
                  };
                  # Bound ONCE per kind and read by both the module key and `__mint`: the key is
                  # built on every application of `__functor` (every instance, every child), and a
                  # mint inside it would run once per application.
                  ownMark = markOf { inherit kind strict plane; };
                  # The keyed module's fields, bound once per kind: the key and, beside it, the
                  # comparison gen-merge's key dedup applies when another occurrence shares the key
                  # (`__keyEq`, gen-merge's protocol): `sealedCollisionEq` over `kindEq`'s subject, the
                  # decision the ancestor map makes, so the one construction reached twice is one
                  # module and two constructions sharing the mark are refused by name, in either order.
                  keyed =
                    if kindParents == [ ] then
                      { }
                    else if !mergeReadsKeyEq then
                      throw "gen-schema: kind '${kind}' composes a parent, so its module is keyed by its mark and publishes the key comparison `__keyEq', and the gen-merge it is evaluated with does not read that key (its `moduleSyntax.structured' does not list `__keyEq'). gen-schema requires a gen-merge carrying the `__keyEq' key-comparison protocol; update the gen-merge input gen-schema is built with."
                    else
                      {
                        key = "gen-schema-kind:${kind}#${ownMark}";
                        __keyEq = {
                          subject = {
                            name = kind;
                            mark = ownMark;
                            inherit (plane) sealed;
                          };
                          decide = keyDecide kind;
                        };
                      };
                in
                # Precedence: computed overrides collections of the same name.
                # __functor is reserved — collections/computed must not use it as a key.
                {
                  # A kind that composes a parent is keyed by its MARK (ADR-0034, identity through the
                  # one mint), so a parent reached on two branches (a diamond) is composed once, and two
                  # kinds with different marks keep two keys and both compose (gen-merge refuses what
                  # conflicts between them). Two declarations sharing a mark share the key: inside a kind
                  # the ancestor map's fold decides that pair, and outside one gen-merge's key dedup
                  # applies the same decision through `__keyEq` (`keyed`).
                  __functor =
                    _:
                    { ... }:
                    {
                      imports = [ merged ];
                    }
                    // keyed;
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
                // guardedComputed
                // {
                  # Applied LAST so the mark cannot be shadowed by a collection or a computed field;
                  # both are refused by name above rather than left to win silently here.
                  __mint = {
                    minted = ownMark;
                  };
                  __sealed = plane.sealed;
                  # the parents as VALUES, read by the ancestor map; the parents as written and the
                  # witness, read by the cycle walk of every kind below
                  __kindImports = kindParents;
                  __kindCycleParents = cycleParents;
                  __kindWitness = kindWitness;
                  __kindAncestors = resolvedOnly kindAncestors;
                }
            );
        };
      in
      self
    )
      checked;

  # OPTIONS door (P1): every formal is optional, closed over `schemaEntryFormals` — the SAME list
  # `mkSchemaEntryType` closes over, so "the option's type is its entry type's construction" holds
  # by construction (see that list's own header comment, above).
  mkSchemaOption =
    args:
    let
      checked = prelude.checkOptions "gen-schema.mkSchemaOption" schemaEntryFormals args;
    in
    # Applied to a native formal, not destructured field-by-field, for the same reason
    # `mkSchemaEntryType` is (den-hoag-jzatq, see its own header comment): every field here is
    # forwarded VERBATIM into `mkSchemaEntryType`'s own `compared` components below, and a
    # `let`-bound selection would hand that door a fresh slot per call rather than the one this
    # door itself was given.
    (
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
        # Built once per call, from the SAME accepted set this door itself just checked against —
        # one list, read twice, so no runtime `==` of two reflections is needed to state the premise.
        entryArgs = {
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
        };
        entry = mkSchemaEntryType entryArgs;
        inner = merge.types.submodule (
          { config, options, ... }:
          {
            # The kinds are typed by this tree's own entry type, which reads a declared parent off
            # `config` — the same kind values `imports = [ config.schema.<p> ]` reads (den-hoag-8c8pr).
            freeformType = merge.types.lazyAttrsOf (mkSchemaEntryTypeIn config entryArgs);

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
              description = "The collection names `mkSchemaOption` refuses, by name, at construction: gen-merge's published module-syntax keys — its structured set (`_declarationKeys`) and its shorthand metadata set, e.g. `require`, which joins `imports` on a shorthand declaration (a collection of either would delete that key from every kind declaration before the module merge sees it) — together with the names gen-schema writes onto the kind value itself (a collection of that name would shadow what this library wrote, or — for `__mint`, applied last — be silently overwritten by it), and the schema's construction formals (a collection of that name would make the formal's key on a kind entry read as a collection, where the declaration-key guard refuses it as a formal). The remedy for all of them is the same: rename the collection.";
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
              description = "The admissible non-collection keys of a kind declaration: gen-merge's published structured-module keys (`merge.moduleSyntax.structured`, which includes `key`). A structured declaration — one carrying `config` or `options` — is read ONLY through this set, this schema's `_collectionKeys`, and one rule that is not a list: any key beginning with `_` is admitted as consumer-private metadata gen-schema must not read. Every other key on a structured declaration is refused by name. A bare top-level option declaration is never read, structured or not: neither module engine collects a top-level `mkOption` as a declaration, so it is refused independently of structuring the moment the surrounding declaration carries ANY module-syntax key at all (`den-hoag-zijk1`). On EVERY declaration, structured or shorthand and on both branches, a top-level key naming one of the schema's construction formals (${builtins.concatStringsSep ", " schemaEntryFormals}) or one of the names gen-schema writes onto the kind value (${builtins.concatStringsSep ", " publishedEntryKeys}) is refused by name: it is fixed by the constructor or published by this library, and written on a kind entry it would land on every instance instead; a module the entry imports is not reached. Exceptions to the `_` prefix rule, refused by name because gen-schema writes them onto every kind value and a declared one is discarded unread: `__mint`, `__sealed`, `__kindImports`, `__kindWitness`, `__kindAncestors` and `__kindCycleParents` always, and `__functor` on a schema built without `mkType`. The guard stands down entirely for a schema constructed with `computed` or `mkType`, whose caller-supplied function receives the raw or stripped defs and so owns a key space gen-schema cannot enumerate. A declaration carrying NO module-syntax key at all is plain data through and through: every key of it is read as config, an option-shaped value among them is no different from any other, and nothing is refused.";
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

                # Containment, read off gen-graph (ADR-0012: one graph notion). `parent` is validated
                # here — the refusal is this library's — and the relation is then handed to gen-graph
                # oriented container -> contained, the orientation of its own `contains` fixture, so
                # `children`, `_roots` and `_leaves` are all answers over ONE accessor.
                kindSet = prelude.genAttrs kindNames (_: true);
                # `materializeParents` is gen-graph's parent map; building it reads every kind's
                # `parent`, so ANY topology read refuses an undeclared parent — the timing the fold
                # this replaced had, kept rather than weakened to a per-kind check.
                parentMap = graph.materializeParents {
                  nodes = kindNames;
                  parent =
                    k:
                    let
                      p = config.${k}.parent;
                    in
                    # The type is tested before the name: the collection is untyped, and a non-string
                    # indexed or interpolated is an interpreter abort, not a refusal (ADR-0025 item 1).
                    # The message names the type and never the value, as gen-graph's `renderId` does.
                    # A string carrying store context is not a kind name either, and cannot index one.
                    if p == null then
                      null
                    else if !(builtins.isString p) then
                      throw "gen-schema: kind '${k}' declares a parent of type ${builtins.typeOf p}, not a kind name"
                    else if builtins.hasContext p then
                      throw "gen-schema: kind '${k}' declares a parent carrying string context, not a kind name"
                    else if !(kindSet ? ${p}) then
                      throw "gen-schema: kind '${k}' declares parent '${p}' which is not a declared kind"
                    else
                      p;
                };
                childrenMap = graph.directDependents {
                  nodes = kindNames;
                  edges = k: prelude.optional (parentMap ? ${k}) parentMap.${k};
                };
                # A complete gen-graph accessor: containment also rides gen-graph's own `parent`
                # dimension (`mkGraph`'s `parents`, `ancestorsOf`), beside the `edges` roots and leaves
                # read.
                containment = {
                  nodes = kindNames;
                  edges = k: childrenMap.${k} or [ ];
                  parent = k: parentMap.${k} or null;
                };
                # Containment is well-founded: a kind that is its own ancestor has no root to hang
                # from, and `_roots`/`_leaves` would drop it without a word. gen-graph's `cycles`
                # names exactly the kinds ON a cycle; a kind nested under one is not itself wrong.
                # Every published read of the containment graph passes through this guard, so it
                # refuses at the timing an undeclared parent does. `_topology` guards each ENTRY, not
                # the set, so its spine (`attrNames`, `?`) answers as it did before the guard.
                cyclic = graph.cycles containment;
                wellFounded =
                  v:
                  if cyclic == [ ] then
                    v
                  else
                    throw "gen-schema: containment cycle among kinds [${prelude.concatStringsSep " " cyclic}] — a kind may not be its own ancestor";
                topology = prelude.genAttrs kindNames (
                  k:
                  wellFounded {
                    parent = containment.parent k;
                    children = containment.edges k;
                  }
                );

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
                # one derivation, not a second spelling. Every kind value carries `inherits`: the entry
                # type writes it on both branches.
                inheritsEdges = prelude.concatMap (
                  k:
                  map (p: {
                    from = k;
                    to = p;
                    type = "inherits";
                    field = null;
                  }) config.${k}.inherits
                ) kindNames;

                edges = parentEdges ++ inheritsEdges ++ map (e: e // { type = "ref"; }) refEdges;

                roots = wellFounded (graph.roots containment);
                leaves = wellFounded (graph.leaves containment);

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
      }
    )
      checked;
in
{
  inherit
    mkSchemaEntryType
    mkSchemaOption
    isSchemaKind
    kindEq
    inheritsResolvedFile
    inheritedModule
    entryReservation
    ;
}
