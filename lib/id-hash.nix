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
  # THE identity-key predicate. It used to need a warning about two derivations agreeing; it no
  # longer does, because there is one. `identityKeysForKind` below is the single derivation, and
  # BOTH readers — the stamp (`mkIdentityModule`, which now takes the key set as data) and the
  # recompute (`identityHashForKind`) — take their keys from it. The agreement is structural rather
  # than maintained, so a key one side counts and the other does not is no longer expressible.
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

  # ★ THE IDENTITY-KEY SET, DERIVED AT THE KIND BOUNDARY — the one derivation, and the boundary is
  # the point. An entity's identity is a function of its KIND's option set (ADR-0016 ruling 5), and a
  # kind's option set is closed the moment the kind is a value. So the keys are derived by evaluating
  # the kind module AS ITS OWN CLOSED STRATUM — one eval, outside the instance fixpoint entirely —
  # rather than read out of the fixpoint that is still collecting declarations. ADR-0033: nothing
  # consumes its own stratum's in-flight output. Reading the instance's merged `options` was exactly
  # that read, and it does not diverge only because the module system gathers declarations before it
  # realizes config, so the read succeeds and returns whatever the sweep happened to reach.
  #
  # WHAT THIS BUYS, BY CONSTRUCTION AND NOT BY CHECK. An option contributed through `extraModules`,
  # through a `refs` binding module, through a refinement, or by any module a caller adds to the
  # instance submodule has NOWHERE TO ATTACH: the key set was a value before those modules were seen.
  # That contribution is not refused, it is inexpressible — the shape `gen-scope/lib/mint.nix` takes
  # with its `kinds` argument, whose comment states the same reach ("an expression with nowhere to
  # attach", "what is owed is dataflow and not a check").
  #
  # ★ THE SOURCE IS THE KIND'S OWN EVALUATION, NOT `kindValue.options`, AND THAT IS A MEASUREMENT.
  # `options` is populated on a kind declared through `mkSchemaOption` and EMPTY on one declared
  # through gen-aspects' `schemaOption`, which keeps its declarations in `__defsModule.imports`. A
  # derivation reading `kindValue.options` therefore mints over `[ "name" ]` alone for every
  # aspect-declared kind — silently disagreeing with the stamp those instances carry, and collapsing
  # two instances differing only in a kind option onto one identity. Both shapes answer `__functor`,
  # so both evaluate here, and the two agree.
  #
  # `name` is prepended because `mkInstanceType` injects it at INSTANCE eval: it is an identity key
  # by construction and is not in the kind's own option set to be reflected out of it. A kind whose
  # instances differ only in `name` collapsing to one identity is the silent-collapse class one door
  # over, so it is added here rather than left to a reflection that cannot see it.
  identityKeysForKind =
    kindValue:
    prelude.sort (a: b: a < b) (
      prelude.unique (
        [ "name" ]
        ++ prelude.attrNames (
          prelude.filterAttrs isPrimitiveOption (merge.evalModuleTree { modules = [ kindValue ]; }).options
        )
      )
    );
in
{
  inherit identityKeysForKind;

  # identityHashForKind kindValue instance — THE recompute path, for a consumer that HAS the kind's processed
  # KIND-VALUE. It takes its keys from `identityKeysForKind`, which is also where the stamp gets them, so it
  # agrees with the stamp by construction rather than by two reflections being kept in step. Routes through
  # the SAME `hashIdentity`, so it can drift from neither.
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
    identity.hashIdentity kindValue.kind (identityKeysForKind kindValue) (k: instance.${k});

  # `identityKeys` is the CLOSED key set, derived once at the kind boundary by `mkInstanceType` and
  # handed in as data. This module reflects nothing: the instance's merged `options` is the in-flight
  # output this construction exists to stop reading, and it is not an argument here any more.
  mkIdentityModule =
    kind: identityKeys:
    { config, ... }:
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
            # Explicit keys are user intent, and they are validated AGAINST THE CLOSED SET — the same
            # boundary the reflection now respects, so the two cannot disagree about what a key is.
            # This is a behaviour change and it is the intended one: `_identity.keys` naming an option
            # contributed on the instance side used to succeed.
            #
            # THE MESSAGE NAMES MEMBERSHIP, NOT A CAUSE, because the closed set excludes for three
            # different reasons and the module holds only the set. A name can be outside it because
            # nothing declares it, because what declares it is not primitive, or because it is
            # declared primitive and excluded (`internal`, `identity = false`, or contributed on the
            # instance side). The predecessor said "is not declared on kind", which is FALSE on the
            # second and third — a kind declaring `tags : listOf str` was told `tags` is undeclared.
            # Membership is true on all three, and the set is printed so the reader sees which.
            validatedExplicitKeys = map (
              k:
              if prelude.elem k identityKeys then
                k
              else
                throw "_identity.keys: '${k}' is not an identity key of kind '${kind}' (identity keys: ${prelude.concatStringsSep ", " identityKeys})"
            ) (prelude.sort (a: b: a < b) explicitKeys);
            keys = if explicitKeys != [ ] then validatedExplicitKeys else identityKeys;
          in
          # ADR-0034: a value or a NAMED refusal, never an abort. The accessor is partial — a key in
          # the set that the instance carries no value for used to reach `config.${k}` and die on a
          # raw missing-attribute error naming a line in this file. `name` is the reachable case and
          # the guard is not written for it alone: `name` is RESERVED rather than declared, injected
          # at instance eval by `mkInstanceType`, so a caller reaching `mkIdentityModule` directly is
          # the one party that can hand over an instance without it. Guarding the accessor rather
          # than that one key costs the same and is total over the whole set.
          identity.hashIdentity kind keys (
            k:
            if config ? ${k} then
              config.${k}
            else
              throw "gen-schema: mkIdentityModule: kind '${kind}' identifies instances by '${k}', which this instance does not declare (identity keys: ${prelude.concatStringsSep ", " keys}); 'name' is reserved and is declared by mkInstanceType"
          );
      };
    };
}
