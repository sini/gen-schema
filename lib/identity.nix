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
{ prelude, merge }:
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
  # returns a JSON-renderable scalar or throws by name.
  #
  # Identity follows the LANGUAGE'S `==`, in both directions — neither coarser nor finer. JSON
  # separates the scalar types natively (`1`, `"1"` and `true` render distinctly), so no type tag is
  # needed; the one thing raw `toJSON` gets wrong is that it renders `1` and `1.0` differently while
  # Nix holds them equal, which is what the integral-float normalisation below repairs. Nothing
  # renders through `toString`, which is coarser than `==` in the other direction: it collapses
  # distinct doubles at six decimal places.
  canonicalScalar =
    v:
    if builtins.isString v || builtins.isBool v || builtins.isInt v then
      v
    else if builtins.isFloat v then
      (
        if !(v > (0.0 - exactBound) && v < exactBound) then
          throw "identity: float outside the exactly-representable integer range"
        else if v == builtins.floor v then
          builtins.floor v
        else
          v
      )
    else
      throw "identity: non-scalar value in an identity position";

  # The PAIRS preimage — a digest of the ⟨label, value⟩ pairs alone. The kind is NOT in it; it rides
  # outside, on the join in `hashIdentity`.
  #
  # Order-insensitivity is BY CONSTRUCTION rather than by a sort the caller owes: the pairs are
  # rendered as a Nix ATTRSET, attrsets carry no order, and `toJSON` emits their keys sorted. A
  # caller supplying `[ "user" "host" ]` and one supplying `[ "host" "user" ]` therefore mint the
  # same node with no sorting anywhere and no contract for a caller to get wrong.
  #
  # `listToAttrs` is what buys that, and it is also what forces the duplicate-label refusal: without
  # it a repeated label would SILENTLY collapse, which trades one order defect for one arity defect.
  # The structural refusals are checked on the LABEL LIST, before any value is forced, so the first
  # error a caller sees names the structural mistake and not a downstream symptom of it.
  canonicalPreimage =
    labels: valueOf:
    let
      labelSet = builtins.attrNames (
        builtins.listToAttrs (
          map (l: {
            name = l;
            value = null;
          }) labels
        )
      );
    in
    if labels == [ ] then
      throw "identity: zero identity keys"
    else if builtins.length labels != builtins.length labelSet then
      throw "identity: duplicate identity key"
    else
      builtins.toJSON (
        builtins.listToAttrs (
          map (l: {
            name = l;
            value = canonicalScalar (valueOf l);
          }) labels
        )
      );

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
    hashIdentity kindValue.kind keys (k: instance.${k});

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
          hashIdentity kind identityKeys (k: config.${k});
      };
    };
}
