{ lib }:
{
  identityModule =
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
              # NB: custom `identity` attr on mkOption survives mergeOptionDecls
              # (tested in identity-false-spike.nix). If a nixpkgs update strips
              # custom attrs, fall back to mkIdentityOpt wrapper per spec Open Question #1.
              && (opt.identity or true);
            reflectedKeys = lib.sort (a: b: a < b) (
              lib.attrNames (lib.filterAttrs isPrimitive options)
            );
            # When explicit keys are provided, validate they reference primitive options
            # to avoid toString on attrsets/lists producing garbage hashes.
            validatedExplicitKeys =
              let
                sorted = lib.sort (a: b: a < b) explicitKeys;
              in
              lib.filter (
                k:
                let
                  opt = options.${k} or null;
                in
                opt != null
                && (opt ? type)
                && lib.elem (opt.type.name or "") primitiveTypeNames
              ) sorted;
            identityKeys = if explicitKeys != [ ] then validatedExplicitKeys else reflectedKeys;
            encode = k: "${k}=${toString config.${k}}";
          in
          builtins.hashString "sha256" "${kind}|${lib.concatMapStringsSep "|" encode identityKeys}";
      };
    };
}
