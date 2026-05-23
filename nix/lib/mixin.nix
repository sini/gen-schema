# First-class mixins (Bracha & Cook 1990).
# Mixins operate on record-algebra records, not NixOS modules.
{
  lib,
  record,
}:
let
  mkMixin =
    {
      requires ? [ ],
      provides ? [ ],
      kinds ? null,
      define,
      name ? "anonymous",
    }:
    {
      __isMixin = true;
      __direction = "smalltalk";
      inherit
        requires
        provides
        kinds
        name
        ;
      delta = parent: record.fromAttrs (define parent);
    };

  beta =
    mixin:
    assert mixin ? __isMixin;
    mixin // { __direction = "beta"; };

  composeMixins =
    mixins:
    let
      computeEffective =
        builtins.foldl'
          (
            acc: m:
            let
              unsatisfied = builtins.filter (r: !(builtins.elem r acc.provided)) m.requires;
            in
            {
              provided = acc.provided ++ m.provides;
              required = acc.required ++ unsatisfied;
            }
          )
          {
            provided = [ ];
            required = [ ];
          }
          mixins;

      # composeMixins [a b c] = c ⋆ (b ⋆ a) via foldl': last-listed provides base,
      # first-listed runs last and has highest priority (wins on conflict).
      # This means: list order = priority order (first wins), and later mixins
      # can access earlier mixins' output via the ⊕ in Bracha's formula.
      composedDelta = builtins.foldl' (acc: m: record.compose m.delta acc) (p: p) mixins;
    in
    {
      __isMixin = true;
      __isComposed = true;
      requires = computeEffective.required;
      provides = computeEffective.provided;
      kinds = null;
      name = "composed";
      __direction = "smalltalk";
      delta = composedDelta;
    };

  applyMixin =
    mixin: kindRecord: kindName:
    let
      kindCheck =
        if mixin.kinds != null && !(builtins.elem kindName mixin.kinds) then
          throw "gen-schema: mixin '${mixin.name}' constrained to kinds [${builtins.concatStringsSep " " mixin.kinds}], got '${kindName}'"
        else
          null;
      structCheck = record.assertSatisfies kindRecord mixin.requires;
    in
    builtins.seq kindCheck (builtins.seq structCheck (
      if mixin.__direction == "beta"
      # Beta: kind (parent) controls — kind fields take precedence over mixin's
      then record.combine kindRecord (mixin.delta kindRecord)
      # Smalltalk: mixin (child) wins — mixin fields override kind's
      else record.mixin mixin.delta kindRecord
    ));
in
{
  inherit
    mkMixin
    beta
    composeMixins
    applyMixin
    ;
}
