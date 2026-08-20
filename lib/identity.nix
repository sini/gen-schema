# mkIdentityModule — content-addressed instance identity.
#
# Injects `id_hash`, a read-only `"<kind>:" + SHA-256` over a kind's primitive
# option values, so two instances are equal iff their identifying fields are.
# Identity keys are discovered by reflection over the kind's primitive options
# (str/int/bool/float), excluding internals and the declared `identity = false`
# opt-outs, or pinned explicitly via `_identity.keys`.
#
# `hashIdentity` below is the one minting authority; nothing else mints.
#
# This is the structural-identity primitive instances add on top of bare schema
# kinds (see instance.nix). Relocated from gen-algebra/module so gen-schema owns
# its full module-system surface; gen-algebra is the pure algebra root.
{
  prelude,
  merge,
  identity,
}:
let
  # 2^53 — the magnitude past which Nix's `==` stops being an equivalence relation across int and
  # float. `9007199254740993 == 9007199254740992.0` and `9007199254740992 == 9007199254740992.0`
  # are both true while `9007199254740993 == 9007199254740992` is false: two ints that are not
  # equal to each other are both equal to one float, because int/float comparison converts through
  # a double and 2^53+1 is not representable in one.
  #
  # The bound is STRICT — 2^53 itself is EXCLUDED — and the reason is that colliding float: it sits
  # AT the bound, not above it. An inclusive bound would admit `9007199254740992.0` as a float,
  # admit `9007199254740993` as an unrestricted int, and then send two `==`-equal admitted values to
  # different digests, i.e. break the identity law INSIDE its own declared domain. Excluding the
  # endpoint removes the float side of the only such pair, which is what leaves ints unrestricted:
  # for |f| < 2^53 an integral f normalises to an exact int, and an int of magnitude above 2^53
  # converts to a double no smaller than 2^53, which no admitted f can equal.
  exactBound = 9007199254740992.0;

  # Every value must be admitted by a PREDICATE before it reaches a builtin, because a builtin's
  # own failure is not a refusal. `builtins.toJSON` on a function, `builtins.floor` outside NixInt
  # range and float division by zero each escape `tryEval` and abort the whole evaluation, so they
  # cannot be caught, attributed to a kind and label, or asserted on in a test — an unnamed abort
  # inside the identity mechanism is a silent failure wearing a loud error. Each branch below either
  # emits a tagged rendering or throws by name.
  #
  # Identity follows the LANGUAGE'S `==`, in both directions — neither coarser nor finer. Nothing
  # renders through `toString`, which is coarser than `==`: it collapses distinct doubles at six
  # decimal places.
  #
  # ★ STRUCTURE IS EMITTED, NEVER DELEGATED, and that is forced rather than preferred.
  # `builtins.toJSON` is NOT structure-preserving on attrsets: a record carrying `outPath` renders
  # as that string ALONE, discarding every sibling attribute, so `{ outPath = "x"; a = 1; }` and
  # `{ outPath = "x"; a = 2; }` both render `"x"` and both equal the rendering of the bare string
  # `"x"` — while Nix `==` distinguishes all three. A composite preimage therefore cannot be
  # `toJSON` of the value. The encoder emits the structure itself and applies `toJSON` only to
  # STRINGS — values and attribute keys — the one position where that coercion cannot arise and
  # where JSON's self-delimiting quoting and escaping is exactly what is wanted.
  #
  # ★ THE TYPE TAG ON EVERY NODE IS WHAT MAKES FORGERY INEXPRESSIBLE rather than blocked case by
  # case: a string can never render as a list or a record because its rendering begins `s`, and a
  # key can never render as a value because it is JSON-quoted and colon-terminated. The scalar
  # semantics are inherited unchanged — the strict |v| < 2^53 float domain, integral-float
  # normalisation to an int, `==` as the reference relation. `null` joins them, tagged `z`: the
  # string "null" tags `s"null"` and an omitted key emits no pair at all, so neither collides.
  #
  # `builtins.attrNames` returns keys sorted, so order-freedom-by-construction recurses to every
  # depth and no caller owes a sort; Nix `==` on lists respects order, so lists encode in order and
  # owe none either.

  # ── the bounds, and the THREE axes they answer ──
  #
  # TWO DECLARED BOUNDS — PREIMAGE LENGTH and WALK DEPTH — each on the quantity it actually
  # measures, and NEITHER IMPLIES THE OTHER: a shared DAG has small depth and an exponential
  # preimage, while a deep thin chain has a small preimage and unbounded depth.
  #
  # ★★ BREADTH IS THE THIRD AXIS, AND IT IS NOT ANSWERED BY A THIRD BOUND. A wide value sits inside
  # both declared bounds — a 31,000-element list is 62,009 preimage characters and two levels deep —
  # yet it escaped them both, because the fold accumulated the budget and the string as THUNK CHAINS
  # that nothing forced until the walk was over. The bounds were not too loose; they had not been
  # EVALUATED. Breadth is answered in `encodeComposite`, by forcing both accumulator fields at every
  # step, and the length budget then does the bounding: it caps member count as a consequence, since every
  # member emits at least its separator. Measured at this budget: 32,763 null members mint, 32,764
  # refuse BY NAME.
  #
  # WHY BOUNDS RATHER THAN CYCLE DETECTION: deciding "reachable from itself" needs an observation
  # of sharing, and Nix's builtin surface offers none — structural `==` on a cyclic value diverges
  # for the same reason this walk would. A bound converts an UNDETECTABLE divergence into a
  # NAMEABLE refusal, which is the only form the mint admits.
  #
  # ★ The depth bound is not a free parameter: it owes `depth × calls-per-node < max-call-depth`,
  # and both factors are evaluator and implementation facts rather than encoding facts. MEASURED on
  # this encoder, with the depth bound lifted and the budget as shipped: a thin chain mints in the
  # low three thousands of levels and, a little above that, aborts UNCATCHABLY with
  # `stack overflow; max-call-depth exceeded` — Nix's own call-depth guard, configured at 10,000,
  # and not a raw C-stack limit. That puts this encoder at ROUGHLY THREE Nix call frames per level,
  # so the constraint reads 512 × 3 < 10,000 and the bound of 512 carries a measured margin of
  # about 6×.
  #
  # ★ THE CROSSOVER IS AN INTERVAL AND MUST NOT BE WRITTEN AS A LEVEL. `max-call-depth` counts a
  # GLOBAL frame budget, not this walk's depth, so whatever else the surrounding evaluation is
  # holding open moves the exact level: independent runs put it a few tens of levels apart. The two
  # figures worth carrying are the STABLE ones — about three frames per level, and about a 6×
  # margin behind the shipped bound — because those survive the harness moving underneath them.
  #
  # ★ THAT MARGIN IS SMALLER THAN IT WAS, AND THE CAUSE IS THE BREADTH FIX ABOVE — recorded because
  # the two are otherwise easy to reason about separately. Forcing each fold step makes the descent
  # STRICT, which spends call frames where the lazy form deferred them: before the forcing the same
  # walk survived past 5,120 levels. An implementation with a heavier per-node call count owes its
  # own margin measurement rather than inheriting this one.
  #
  # ★ THE PRICE IS REAL AND IS NOT HIDDEN: a value with FEW DISTINCT NODES is refused when its
  # EXPANSION exceeds the budget, because what a walk pays is the expansion and not the node count.
  # Every derivation — every package — is excluded outright, and so is every self-referential
  # value. An ordinary identity record encodes to a few dozen characters, so the budget carries
  # about three orders of magnitude of headroom over the population that actually mints.
  identityBudget = 65536;
  identityDepth = 512;

  # Emit one rendered fragment against the REMAINING PREIMAGE CHARACTERS. Exhaustion is a refusal
  # by name, so a refusal costs the budget rather than the expansion it declined to build.
  emit =
    b: str:
    let
      rest = b - builtins.stringLength str;
    in
    if rest < 0 then
      throw "identity: preimage exceeds the identity budget"
    else
      {
        s = str;
        b = rest;
      };

  # A composite renders as an opening tag, one member fragment per member each followed by the
  # separator, and a closing tag — with the budget THREADED through every step. Threading is why
  # the encoder and the bound are ONE mechanism and not two: a plain map-fold cannot carry state
  # and therefore cannot carry the bound.
  #
  # ★★ BOTH ACCUMULATOR FIELDS ARE FORCED AT EVERY STEP, AND THAT IS WHAT BOUNDS BREADTH — the
  # third axis, which neither the length budget nor the depth bound reaches on its own.
  #
  # `foldl'` forces the accumulator to WHNF, and it is easy to read that as "the fold is strict".
  # It is not strict in what matters here: the accumulator is an attrset LITERAL, so it is ALREADY
  # in WHNF and forcing it does nothing to its fields. What the fold leaves behind is TWO chains of
  # unforced thunks, one link per member — the threaded budget and the accumulated concatenation.
  # Nothing examines either until the walk is over, so a WIDE value escapes both bounds: forcing an
  # n-link concatenation chain recurses n frames into the C stack and OVERFLOWS UNCATCHABLY.
  # Measured before this forcing: a 31,000-element list — preimage 62,009 characters, inside the
  # budget, and depth 2, inside the depth bound — aborted with `stack overflow`, escaping `tryEval`;
  # so did a list whose preimage was over budget, because the budget was still a thunk when the
  # stack ran out.
  #
  # Forcing both fields per round is ADR-0022's own probe constraint arriving in the identity
  # domain: every round-loop accumulator field is forced per round, so state cannot accrete as a
  # thunk chain the loop never inspects. It also makes the LENGTH bound honest — the budget is now
  # spent AS the walk proceeds, so a refusal fires at the member that exhausts it rather than after
  # the whole expansion has been described.
  encodeComposite =
    b: open: close: renderMember: members:
    let
      opened = emit b open;
      stepped = builtins.foldl' (
        acc: m:
        let
          rendered = renderMember acc.b m;
          separated = emit rendered.b ",";
          s = acc.s + rendered.s + separated.s;
          b = separated.b;
        in
        # Both fields, both flat values: a string and an int, so WHNF is full evaluation and no
        # deep force is owed.
        #
        # ★ THE TWO ARE NOT SYMMETRIC, AND SAYING THEY WERE OVERSTATED THE SECOND. `seq s` is the
        # load-bearing one: forcing the string forces `separated.s`, which is an `emit` result, and
        # `emit` cannot produce its string without first computing `rest` and testing `rest < 0` —
        # so the budget is dragged along transitively. Measured, one variant per arm: `seq s` ALONE
        # mints a 31,000-member value; `seq b` alone and neither both abort uncatchably. `seq b` is
        # therefore belt-and-braces over a chain `seq s` already collapses. It is kept because the
        # transitive argument depends on `emit`'s internals, and a future `emit` that produced its
        # string without consulting the budget would silently un-bound this axis — the redundant
        # force errs in the safe direction and costs one already-forced int.
        builtins.seq s (builtins.seq b { inherit s b; })
      ) { inherit (opened) s b; } members;
      closed = emit stepped.b close;
    in
    {
      s = stepped.s + closed.s;
      b = closed.b;
    };

  # One field of a record: the JSON-rendered key, a colon, then the field's own encoding. Shared by
  # the caller-data walk and by the mint's own outer frame below, so ONE record grammar exists.
  encodeField =
    d: b: v: k:
    let
      key = emit b (builtins.toJSON k + ":");
      val = canonicalEncode d key.b v.${k};
    in
    {
      s = key.s + val.s;
      b = val.b;
    };

  # canonicalEncode : depth -> budget -> value -> { s; b; }
  canonicalEncode =
    d: b: v:
    if d > identityDepth then
      throw "identity: value nests deeper than the identity depth bound"
    else if builtins.isString v then
      emit b ("s" + builtins.toJSON v)
    else if builtins.isBool v then
      emit b (if v then "b1" else "b0")
    else if builtins.isInt v then
      emit b ("i" + builtins.toString v)
    else if builtins.isFloat v then
      (
        if !(v > (0.0 - exactBound) && v < exactBound) then
          throw "identity: float outside the exactly-representable integer range"
        else if v == builtins.floor v then
          emit b ("i" + builtins.toString (builtins.floor v))
        else
          emit b ("f" + builtins.toJSON v)
      )
    else if v == null then
      emit b "z"
    else if builtins.isList v then
      encodeComposite b "[" "]" (b': x: canonicalEncode (d + 1) b' x) v
    else if builtins.isAttrs v then
      # A DERIVATION IS REFUSED BY TYPE TEST, BEFORE ANY DESCENT. A derivation's output attribute is
      # self-referential (`drv.out.out.out.name` resolves), so an unbounded walk over one does not
      # terminate. This gate exists for TERMINATION and not for forgery — the tagged encoding
      # already closes the `outPath` channel.
      #
      # ★★ THE TEST IS THE FULL THREE-ATTRIBUTE SHAPE, AND THE NARROWER FORM WAS DISCONTINUOUS UNDER
      # NESTING. Testing `type` alone refuses any record whose `type` field happens to hold the
      # string "derivation" — an ordinary declaration, since a `str` option may be named anything.
      # That made ADMISSIBILITY DEPEND ON POSITION rather than on the value: measured, the record
      # `{ type = "derivation"; n = 1; }` MINTED as the mint's own outer frame and REFUSED one level
      # down, with the same shape carrying `type = "ordinary"` minting at both. Position-dependent
      # admissibility is what ADR-0034's "inert composites are admitted" cannot survive, so the
      # population it applies to had to shrink.
      #
      # ★ IT SHRANK; IT DID NOT VANISH, and the residue is stated rather than left to be found. The
      # mint's outer FRAME never reaches this gate at all — it is synthesized by the mint and is not
      # caller data — so a record of the full three-attribute shape STILL mints at the frame while
      # refusing everywhere caller data can put it. `test-derivation-shape-refused-wherever-caller-
      # data-reaches` pins exactly that, frame arm included. What changed is which values sit in the
      # discontinuous population: it was every record whose `type` field held a string, which is an
      # ordinary declaration, and it is now only the full derivation shape, which no kind declares
      # by accident. The remaining discontinuity errs toward MINTING a synthesized frame rather than
      # refusing a legitimate value, which is the direction that costs an identity nothing.
      #
      # Requiring `drvPath` and `outPath` alongside `type` costs no termination guarantee: what does
      # not terminate is the self-referential output attribute, and a record carrying all three
      # WITHOUT that structure is finite and bounded like any other. The three-attribute shape is
      # what an actual derivation has, so every value the gate exists to stop is still stopped.
      # Presence tests do not force, so widening the gate forces nothing new either.
      if (v.type or null) == "derivation" && v ? drvPath && v ? outPath then
        throw "identity: a derivation in an identity position"
      else
        encodeComposite b "{" "}" (b': k: encodeField (d + 1) b' v k) (builtins.attrNames v)
    else
      # Lambdas and paths land here, named by their own type. A lambda has no eliminator in Nix — no
      # builtin exposes a closure's captured environment or its body — so no preimage over one can
      # be TOTAL, and an identity minted over a partial preimage merges behaviourally distinct
      # values. A path is refused because `toJSON` on a file path silently copies it to the store
      # and on a directory path aborts uncatchably.
      throw "identity: a ${builtins.typeOf v} in an identity position";

  # The PAIRS preimage — a digest of the ⟨label, value⟩ pairs alone. The kind is NOT in it; it rides
  # outside, on the join in `hashIdentity`.
  #
  # Order-insensitivity is BY CONSTRUCTION rather than by a sort the caller owes: the pairs are
  # rendered as a Nix ATTRSET and `attrNames` yields its keys sorted. A caller supplying
  # `[ "user" "host" ]` and one supplying `[ "host" "user" ]` therefore mint the same node with no
  # sorting anywhere and no contract for a caller to get wrong.
  #
  # `listToAttrs` is what buys that, and it is also what forces the duplicate-label refusal: without
  # it a repeated label would SILENTLY collapse, which trades one order defect for one arity defect.
  # The structural refusals are checked on the LABEL LIST, before any value is forced, so the first
  # error a caller sees names the structural mistake and not a downstream symptom of it.
  #
  # ★ THE OUTER FRAME IS THE MINT'S OWN, so it is rendered by `encodeComposite` DIRECTLY rather than
  # by handing a synthesized record back to `canonicalEncode`. Routing it through the walk would
  # apply the derivation gate to a record the mint just built, and a kind carrying an ordinary
  # `type` option whose value happened to be the string "derivation" would then be refused an
  # identity it is entitled to. The frame is not caller data; its FIELDS are, and those take the
  # full walk from depth 1.
  canonicalPreimage =
    labels: valueOf:
    let
      pairs = builtins.listToAttrs (
        map (l: {
          name = l;
          value = valueOf l;
        }) labels
      );
    in
    if labels == [ ] then
      throw "identity: zero identity keys"
    else if builtins.length labels != builtins.length (builtins.attrNames pairs) then
      throw "identity: duplicate identity key"
    else
      (encodeComposite identityBudget "{" "}" (b: k: encodeField 1 b pairs k) (builtins.attrNames pairs))
      .s;

  # The SINGLE minting authority. An identity is the kind tag joined to a digest of the pairs:
  #
  #     identity = "<kind>:" + sha256(<pairs preimage>)
  #
  # The tag rides OUTSIDE the digest. What identity has to deliver here is DISTINCTNESS, not
  # cryptographic integrity, and since nothing but this function mints there is no second writer for
  # a hashed-in prefix to authenticate against. What riding outside buys is that an identity says
  # what it is: the kind is recoverable by splitting on the first colon, with no reverse lookup, and
  # a trace reads. The digest region is consequently kind-INDEPENDENT — two relations over identical
  # relata share it — so the identity is the WHOLE STRING and a consumer that slices the digest out
  # of it is not comparing identities.
  #
  # That join is the one place a value could reach the structure, and it is closed on the kind side
  # by refusing `:` in a kind name. Inside the pairs preimage the same class is closed by a
  # different mechanism — JSON is self-delimiting, quoting string values and escaping internal
  # quotes and backslashes — which is why a VALUE may contain a colon and a KIND may not. Relatum
  # identities are themselves colon-bearing, so that asymmetry is load-bearing rather than
  # incidental: data is escaped, structure is constrained.
  hashIdentity =
    kind: labels: valueOf:
    if kind == "" then
      throw "identity: empty relation kind"
    else if builtins.match "[^:]*" kind == null then
      throw "identity: ':' is the kind separator and is refused in a kind name"
    else
      "${kind}:" + builtins.hashString "sha256" (canonicalPreimage labels valueOf);

  # THE identity-key predicate — ONE definition, because the option-reflecting derivations must agree
  # and two copies of a list is how they stop agreeing. `mkIdentityModule` reflects the INSTANCE's
  # merged options to stamp `id_hash`; `identityHashForKind` reflects the KIND VALUE's options to
  # recompute it. A key one side counts and the other does not is a hash mismatch on every instance
  # of that kind — and it is silent, because both answers are well-formed hashes.
  #
  # Reflection dispatches on the option's type NAME. gen-types leaf checkers name primitives
  # "string"/"int"/"bool"; nixpkgs `lib.types` names the same primitive "str"/"int"/"bool". Both
  # spellings are accepted so a kind declared with EITHER type system reflects identically — den
  # declares every entity option with nixpkgs `lib.types`, so a nixpkgs-str field (e.g. a home's
  # `system`) must reflect, else same-named instances that differ only in it collapse to one id_hash.
  #
  # `float` is a primitive here for the same reason the encoder normalises integral floats: identity
  # follows the language's `==`, and a float-typed option is a declared field two instances can
  # differ in. Both type systems spell it "float". The encoder's strict |v| < 2^53 domain is
  # therefore reachable from an ordinary declaration, and refuses by name at mint time.
  primitiveTypeNames = [
    "string"
    "str"
    "int"
    "bool"
    "float"
  ];
  isPrimitiveOption =
    name: opt:
    !(prelude.hasPrefix "_" name)
    && (opt ? type)
    && prelude.elem (opt.type.name or "") primitiveTypeNames
    && !(opt.internal or false)
    && (opt.identity or true);
in
{
  inherit hashIdentity;

  # identityHashForKind kindValue instance — THE recompute path, for a consumer that HAS the kind's processed
  # KIND-VALUE. It reflects the KIND's primitive options — honoring `identity = false` and `internal`, the SAME
  # reflection `mkIdentityModule` performs — so it agrees with the stamp by construction. Routes through the
  # SAME `hashIdentity`, so it can drift from neither.
  #
  # It is the SOLE recompute path because there is one minting authority and a second derivation that can
  # disagree with the first is one derivation too many. A value-reflecting twin — keeping any attribute whose
  # VALUE is primitive — cannot honour that: an instance value carries no option metadata, so it can see
  # neither `internal` nor the `identity = false` opt-out, and a method's return is a plain primitive
  # attribute in `config` that it would admit as an identity key. Kind-DISCOVERY (recompute per candidate
  # kind, match the carried `id_hash`) is served here, by a caller holding the kind value.
  #
  # DISCOVERY PROPERTY: a recompute that does NOT match the carried hash means the kind guess is wrong — and
  # since a WRONG-kind false match needs a sha256 collision across different preimages (negligible), a
  # non-match is a reliable "not this kind". If two gen-schema pins' formulas ever diverged, EVERY instance
  # would mismatch → the namespace matches NO kind → the consumer's strict gate aborts NAMED (a loud MISS,
  # never a misclassification). Reflection path only (a kind pinning explicit `_identity.keys` is the sole
  # divergence — the instance carries those, not the kind-value).
  identityHashForKind =
    kindValue: instance:
    let
      # `mkInstanceType` injects `name` (a primitive identity key) at INSTANCE eval, so it is NOT in the
      # kind-value's user `options` — add it explicitly to match `mkIdentityModule`'s full-options reflection.
      keys = prelude.sort (a: b: a < b) (
        prelude.unique (
          [ "name" ] ++ prelude.attrNames (prelude.filterAttrs isPrimitiveOption (kindValue.options or { }))
        )
      );
    in
    identity.hashIdentity kindValue.kind keys (k: instance.${k});

  mkIdentityModule =
    kind:
    { config, options, ... }:
    {
      # `_identity` is a submodule option (not a bare nested `options._identity.keys`):
      # gen-merge collects declared options with a flat `//` and does not descend into
      # nested option sets, so the `keys` sub-option must live inside a submodule to get
      # its listOf-merge + `apply = unique` semantics. Reads stay `config._identity.keys`.
      options._identity = merge.mkOption {
        default = { };
        description = "Identity configuration.";
        type = merge.types.submodule {
          options.keys = merge.mkOption {
            type = merge.types.listOf merge.types.str;
            default = [ ];
            description = "Explicit identity keys. Empty = use reflection.";
            apply = prelude.unique;
          };
        };
      };

      options.id_hash = merge.mkOption {
        readOnly = true;
        internal = true;
        type = merge.types.str;
        default =
          let
            explicitKeys = config._identity.keys;
            reflectedKeys = prelude.sort (a: b: a < b) (
              prelude.attrNames (prelude.filterAttrs isPrimitiveOption options)
            );
            # Explicit keys are user intent — validate they exist and are primitive.
            # Throw on invalid keys rather than silently dropping them.
            validatedExplicitKeys =
              let
                sorted = prelude.sort (a: b: a < b) explicitKeys;
              in
              map (
                k:
                let
                  opt = options.${k} or null;
                in
                if opt == null then
                  throw "_identity.keys: '${k}' is not declared on kind '${kind}'"
                else if !(opt ? type) || !(prelude.elem (opt.type.name or "") primitiveTypeNames) then
                  throw "_identity.keys: '${k}' on kind '${kind}' is not a primitive type (str/int/bool/float)"
                else
                  k
              ) sorted;
            identityKeys = if explicitKeys != [ ] then validatedExplicitKeys else reflectedKeys;
          in
          identity.hashIdentity kind identityKeys (k: config.${k});
      };
    };
}
