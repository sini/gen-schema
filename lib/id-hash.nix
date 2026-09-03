# mkIdentityModule — content-addressed instance identity, the REFLECTION half.
#
# Injects `id_hash`, a read-only `"<kind>:" + SHA-256` over a kind's primitive
# option values, so two instances are equal iff their identifying fields are.
# Identity keys are discovered by reflection over the kind's primitive options
# (str/int/bool/float), excluding internals and the declared `identity = false`
# opt-outs, or pinned explicitly via `_identity.keys`.
#
# ★ THE MINT IS NOT HERE. `hashIdentity` — the substrate's one minting authority,
# ADR-0016 ruling 5 — lives in `gen-identity`, a dependency-free leaf, and arrives
# injected as `identity`. Nothing in this file mints, and nothing re-exports the
# mint under gen-schema's name: re-exporting another library's value re-exports its
# build (ADR-0014), so a consumer that wants the mint takes the leaf.
#
# What this file owns is the half that is a MODULE-SYSTEM concern in every part —
# deciding WHICH of a kind's declared options are identity keys, recomputing an
# instance's hash from a kind value, and stamping `id_hash`. It reads option
# metadata (`opt.type.name`, `opt.internal`, the `identity = false` opt-out) and
# builds options with `merge.mkOption`. It CONSTRUCTS with the injected mint inside
# gen-schema's own evaluation, which is ADR-0014's constructing arm.
#
# This is the structural-identity primitive instances add on top of bare schema
# kinds (see instance.nix).
{
  prelude,
  merge,
  identity,
}:
let
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
    _name: opt:
    (opt ? type)
    && prelude.elem (opt.type.name or "") primitiveTypeNames
    && !(opt.internal or false)
    && (opt.identity or true);
in
{
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
