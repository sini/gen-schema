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
          # A method is NOT an identity key. The identity preimage is a kind's option-reflected
          # identity keys minus the declared opt-outs; a method is an option only because that is
          # how its return reaches `config`, and its return is derived from the instance rather
          # than declared on it. Marking it here rather than filtering method names downstream
          # keeps ONE exclusion channel (the opt-out the reflection already reads) and is by
          # construction — a method cannot be declared without passing through this `mkOption`.
          #
          # Without this the opt-out stops being a boundary at all: a method is an arbitrary
          # function of config, so a primitive-typed method reading an `identity = false` field
          # re-admits that field's value through its own return, and declaring the method MOVES
          # the identity of an otherwise unchanged instance.
          identity = false;
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
