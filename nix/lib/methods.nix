{ lib }:
let
  schemaFn = description: type: fn: {
    inherit description type fn;
  };

  mkMethodsModule =
    kind: allMethods:
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
          argNames = lib.attrNames args;
          missingArgs = lib.filter (n: !(config ? ${n})) argNames;
          resolved = lib.genAttrs argNames (n: config.${n});
        in
        if missingArgs != [ ] then
          throw "method '${name}' on ${kind}: references config keys ${
            lib.concatMapStringsSep ", " (a: "'${a}'") missingArgs
          } which are not declared on this kind"
        else
          m.fn resolved
      ) allMethods;
    };
in
{
  inherit schemaFn mkMethodsModule;
}
