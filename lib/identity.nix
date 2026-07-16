# mkIdentityModule — content-addressed instance identity.
#
# Injects `id_hash`, a read-only SHA-256 over a kind's primitive option values,
# so two instances are equal iff their identifying fields are. Identity keys are
# discovered by reflection over the kind's primitive options (str/int/bool),
# excluding internals, or pinned explicitly via `_identity.keys`.
#
# This is the structural-identity primitive instances add on top of bare schema
# kinds (see instance.nix). Relocated from gen-algebra/module so gen-schema owns
# its full module-system surface; gen-algebra is the pure algebra root.
{ prelude, merge }:
let
  # The content-address FORMULA — the SINGLE definition both `mkIdentityModule` (identity keys reflected
  # from a kind's options) and `identityHashFor` (reflected from an instance value) hash through, so the
  # two derivations can NEVER drift from each other. `<kind>|<k1=v1>|<k2=v2>…` over the sorted identity keys.
  hashIdentity =
    kind: keys: valueOf:
    builtins.hashString "sha256" "${kind}|${
      prelude.concatMapStringsSep "|" (k: "${k}=${toString (valueOf k)}") keys
    }";
in
{
  inherit hashIdentity;

  # identityHashFor kind instance — recompute an instance's content-addressed `id_hash` from its VALUE +
  # kind NAME, for EXTERNAL kind-DISCOVERY: a consumer holding an instance value but not its kind (e.g. the
  # den-compat shim mapping a config-chosen registry key back to the kind it holds) recomputes the hash for
  # each candidate kind and matches the instance's carried `id_hash`. Reflects the instance's own primitive
  # fields (string/int/bool), matching `mkIdentityModule`'s hash for any kind whose identity keys are its
  # primitive options — the common case; a kind pinning `identity = false` on a primitive is the sole
  # divergence (documented). Goes through the SAME `hashIdentity` formula, so it cannot drift from the
  # module. DISCOVERY PROPERTY: a recompute that does NOT match the carried hash means the kind guess is
  # wrong — and since a WRONG-kind false match needs a sha256 collision across different preimages
  # (negligible), a non-match is a reliable "not this kind". If two gen-schema pins' formulas ever diverged,
  # EVERY instance would mismatch → the namespace matches NO kind → the consumer's strict gate aborts NAMED
  # (a loud MISS, never a misclassification).
  identityHashFor =
    kind: instance:
    let
      isPrim = v: builtins.isString v || builtins.isInt v || builtins.isBool v;
      keys = prelude.sort (a: b: a < b) (
        builtins.filter (
          k: !(prelude.hasPrefix "_" k) && k != "id_hash" && isPrim (instance.${k} or null)
        ) (builtins.attrNames instance)
      );
    in
    hashIdentity kind keys (k: instance.${k});

  # identityHashForKind kindValue instance — the OPTION-LEVEL EXACT twin of `identityHashFor`, for a consumer
  # that HAS the kind's processed KIND-VALUE (e.g. the den-compat shim after schema processing). It reflects
  # the KIND's primitive options — honoring `identity = false` and `internal`, the SAME reflection
  # `mkIdentityModule` performs — so it is EXACT where `identityHashFor` (reflecting the instance's own present
  # fields) can only approximate. Routes through the SAME `hashIdentity`, so it can drift from neither. Same
  # discovery/skew loudness (a non-match = "not this kind"; formula skew ⇒ every instance misses). Reflection
  # path only (a kind pinning explicit `_identity.keys` is the sole divergence — the instance carries those,
  # not the kind-value).
  identityHashForKind =
    kindValue: instance:
    let
      primitiveTypeNames = [
        "string"
        "int"
        "bool"
      ];
      isPrimitive =
        name: opt:
        !(prelude.hasPrefix "_" name)
        && (opt ? type)
        && prelude.elem (opt.type.name or "") primitiveTypeNames
        && !(opt.internal or false)
        && (opt.identity or true);
      # `mkInstanceType` injects `name` (a primitive identity key) at INSTANCE eval, so it is NOT in the
      # kind-value's user `options` — add it explicitly to match `mkIdentityModule`'s full-options reflection.
      keys = prelude.sort (a: b: a < b) (
        prelude.unique (
          [ "name" ] ++ prelude.attrNames (prelude.filterAttrs isPrimitive (kindValue.options or { }))
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
            # id-hash reflection over primitive fields dispatches on the option's type NAME. gen-types
            # leaf checkers name primitives "string"/"int"/"bool"; nixpkgs `lib.types` name the same
            # primitive "str"/"int"/"bool". Both are accepted so a kind declared with EITHER type system
            # reflects identically — den declares every entity option with nixpkgs `lib.types`, so a
            # nixpkgs-str field (e.g. a home's `system`) must reflect, else same-named instances that
            # differ only in it collapse to one id_hash.
            primitiveTypeNames = [
              "string"
              "str"
              "int"
              "bool"
            ];
            isPrimitive =
              name: opt:
              !(prelude.hasPrefix "_" name)
              && (opt ? type)
              && prelude.elem (opt.type.name or "") primitiveTypeNames
              && !(opt.internal or false)
              && (opt.identity or true);
            reflectedKeys = prelude.sort (a: b: a < b) (
              prelude.attrNames (prelude.filterAttrs isPrimitive options)
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
                  throw "_identity.keys: '${k}' on kind '${kind}' is not a primitive type (str/int/bool)"
                else
                  k
              ) sorted;
            identityKeys = if explicitKeys != [ ] then validatedExplicitKeys else reflectedKeys;
          in
          hashIdentity kind identityKeys (k: config.${k});
      };
    };
}
