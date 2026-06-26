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
{ lib }:
{
  mkIdentityModule =
    kind:
    { config, options, ... }:
    {
      options._identity.keys = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Explicit identity keys. Empty = use reflection.";
        apply = lib.unique;
      };

      options.id_hash = lib.mkOption {
        readOnly = true;
        internal = true;
        type = lib.types.str;
        default =
          let
            explicitKeys = config._identity.keys;
            primitiveTypeNames = [
              "str"
              "int"
              "bool"
            ];
            isPrimitive =
              name: opt:
              !(lib.hasPrefix "_" name)
              && (opt ? type)
              && lib.elem (opt.type.name or "") primitiveTypeNames
              && !(opt.internal or false)
              && (opt.identity or true);
            reflectedKeys = lib.sort (a: b: a < b) (lib.attrNames (lib.filterAttrs isPrimitive options));
            # Explicit keys are user intent — validate they exist and are primitive.
            # Throw on invalid keys rather than silently dropping them.
            validatedExplicitKeys =
              let
                sorted = lib.sort (a: b: a < b) explicitKeys;
              in
              map (
                k:
                let
                  opt = options.${k} or null;
                in
                if opt == null then
                  throw "_identity.keys: '${k}' is not declared on kind '${kind}'"
                else if !(opt ? type) || !(lib.elem (opt.type.name or "") primitiveTypeNames) then
                  throw "_identity.keys: '${k}' on kind '${kind}' is not a primitive type (str/int/bool)"
                else
                  k
              ) sorted;
            identityKeys = if explicitKeys != [ ] then validatedExplicitKeys else reflectedKeys;
            encode = k: "${k}=${toString config.${k}}";
          in
          builtins.hashString "sha256" "${kind}|${lib.concatMapStringsSep "|" encode identityKeys}";
      };
    };
}
