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
            isPrimitive =
              name: opt:
              !(lib.hasPrefix "_" name)
              && (opt ? type)
              && builtins.elem (opt.type.name or "") [
                "str"
                "int"
                "bool"
              ]
              && !(opt.internal or false)
              && (opt.identity or true);
            reflectedKeys = lib.sort (a: b: a < b) (builtins.attrNames (lib.filterAttrs isPrimitive options));
            identityKeys = if explicitKeys != [ ] then lib.sort (a: b: a < b) explicitKeys else reflectedKeys;
            encode = k: "${k}=${toString config.${k}}";
          in
          builtins.hashString "sha256" "${kind}|${lib.concatMapStringsSep "|" encode identityKeys}";
      };
    };
}
