{ prelude, merge }:
let
  schemaFn = description: type: fn: {
    inherit description type fn;
  };

  mkMethodsModule =
    kind: allMethods:
    { config, ... }:
    {
      options = prelude.mapAttrs (
        _name: m:
        merge.mkOption {
          inherit (m) description type;
          readOnly = true;
        }
      ) allMethods;

      config = prelude.mapAttrs (
        name: m:
        let
          args = builtins.functionArgs m.fn;
          argNames = prelude.attrNames args;
          missingArgs = prelude.filter (n: !(config ? ${n})) argNames;
        in
        if missingArgs != [ ] then
          throw "gen-schema: method '${name}' on ${kind}: references config keys ${
            prelude.concatMapStringsSep ", " (a: "'${a}'") missingArgs
          } which are not declared on this kind"
        else
          let
            resolved = prelude.genAttrs argNames (n: config.${n});
          in
          m.fn resolved
      ) allMethods;
    };
in
{
  inherit schemaFn mkMethodsModule;
}
