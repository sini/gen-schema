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
{
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
            # gen-types leaf CHECKERS name primitives "string"/"int"/"bool" (NOT nixpkgs'
            # "str"): id-hash reflection over primitive fields dispatches on that name.
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
            encode = k: "${k}=${toString config.${k}}";
          in
          builtins.hashString "sha256" "${kind}|${prelude.concatMapStringsSep "|" encode identityKeys}";
      };
    };
}
