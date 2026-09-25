# den-hoag-ciu4r (ADR-0025). A computed field is splatted OVER the record `mkSchemaEntryType` writes
# onto the kind value, on both branches, so a computed field named for one of those keys replaced
# it with no signal (measured at a90bc54: a computed `options` or `refs` read back as the computed
# value on both arms). The door reads `kindResultKeys`; this cell quantifies over the PUBLISHED
# superset `_reservedCollectionKeys` (`declarationKeys ++ kindResultKeys`) and pins which names a
# computed field may not take, so a name added to `kindResultKeys` moves the refused set here.
# The names only `declarationKeys` contributes are not written onto the kind value and stay free.
# The messages are pinned in `ci/tests-error.nix`, `computed-field-shadow-refusals`.
{
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) mkSchemaOption;

  evalWith =
    args:
    (genMerge.evalModuleTree {
      modules = [
        { options.schema = mkSchemaOption args; }
        { config.schema.host = { }; }
      ];
    }).config.schema;

  mkType =
    { ... }:
    {
      options.role = genMerge.mkOption {
        type = genMerge.types.str;
        default = "x";
      };
    };

  names = (evalWith { })._reservedCollectionKeys;

  # `.strict` is read because `// computedFields` forces the door whatever key is read.
  refusedOn =
    args:
    builtins.filter (
      k:
      !(builtins.tryEval (
        builtins.deepSeq
          (evalWith (
            args
            // {
              computed = _: _: { ${k} = "COMPUTED"; };
            }
          )).host.strict
          true
      )).success
    ) names;

  refused = [
    "__functor"
    "__mint"
    "__sealed"
    "keySemantics"
    "kind"
    "mixins"
    "options"
    "refinements"
    "refs"
    "strict"
  ];
in
{
  flake.tests.computed-field-keys = {
    test-default-arm-refuses-every-kind-result-key = {
      expr = refusedOn { };
      expected = refused;
    };
    test-mkType-arm-refuses-every-kind-result-key = {
      expr = refusedOn { inherit mkType; };
      expected = refused;
    };
    # The control: a free computed name still lands, on both arms.
    test-free-computed-name-is-accepted = {
      expr = map (args: (evalWith (args // { computed = _: _: { freeName = 1; }; })).host.freeName) [
        { }
        { inherit mkType; }
      ];
      expected = [
        1
        1
      ];
    };
  };
}
