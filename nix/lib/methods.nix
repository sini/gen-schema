{ lib }:
let
  schemaFn = description: type: fn: {
    _schemaMethod = true;
    inherit description type fn;
  };

  mkMethodsModule =
    allMethods:
    { config, ... }:
    {
      options = lib.mapAttrs (
        name: m:
        lib.mkOption {
          inherit (m) description type;
          readOnly = true;
        }
      ) allMethods;

      config = lib.mapAttrs (
        name: m:
        let
          args = builtins.functionArgs m.fn;
          argNames = builtins.attrNames args;
          missingArgs = builtins.filter (n: !(config ? ${n})) argNames;
          resolved = lib.genAttrs argNames (n: config.${n});
        in
        if missingArgs != [ ] then
          throw "method '${name}': references config keys ${
            builtins.concatStringsSep ", " (map (a: "'${a}'") missingArgs)
          } which are not declared on this kind"
        else
          m.fn resolved
      ) allMethods;
    };
in
{
  inherit schemaFn mkMethodsModule;
}
