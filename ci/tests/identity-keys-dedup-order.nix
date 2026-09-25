{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) mkIdentityModule identityKeysForKind;
  # The door takes the KIND DECLARATION, never its name. `mkEval kind modules`: the HEAD of the list
  # is the kind's declarations, evaluated through `evalSchema` as the kind `kind`; the TAIL is the
  # instance's definitions. See ci/tests/identity-hash.nix for the full note, including why a cell
  # comparing two DECLARATIONS recomputes under one kind rather than comparing two stamps.
  mkKind =
    kind: decl:
    (genSchema.evalSchema {
      modules = [ { config.schema.${kind} = decl; } ];
    }).${kind};
  mkEval =
    kind: modules:
    let
      kindValue = mkKind kind (builtins.head modules);
    in
    genMerge.evalModuleTree {
      modules = [ (mkIdentityModule kindValue (identityKeysForKind { } kindValue)) ] ++ modules;
    }
    // {
      inherit kindValue;
    };

  # den-hoag-ngsq — gen-schema's own consumption of `prelude.unique` was measured BLIND to a
  # no-dedup or order-broken prelude (den-hoag-34zp implgate r1/r2, den-hoag-ndp6's sibling
  # class): both `_identity.keys` sites re-sort their result, so order is unobservable by
  # construction, and dedup needs a config no existing fixture provides — a duplicate,
  # non-sorted `_identity.keys` on a kind that declares both names as primitive options.
  #
  # `_identity.keys` (`lib/id-hash.nix`'s `apply = prelude.unique`) is read directly, BEFORE the
  # downstream `validatedExplicitKeys` re-sort and the `id_hash` computation — a value-level
  # check, not an abort-level one. A no-dedup prelude keeps the duplicate (3 elements); an
  # order-broken prelude still dedups but returns sort-order rather than insertion-order
  # (`["rack","zone"]` instead of `["zone","rack"]`) — both differ from the literal expected
  # value below, so this single arm discriminates both axes.
  evalDedupOrder = mkEval "host" [
    {
      options.zone = genMerge.mkOption { type = genMerge.types.str; };
      options.rack = genMerge.mkOption { type = genMerge.types.str; };
    }
    {
      config.zone = "a";
      config.rack = "b";
      config._identity.keys = [
        "zone"
        "rack"
        "zone"
      ];
    }
  ];
in
{
  flake.tests.identity-keys-dedup-order.test-identity-keys-deduped = {
    expr = evalDedupOrder.config._identity.keys;
    expected = [
      "zone"
      "rack"
    ];
  };
}
