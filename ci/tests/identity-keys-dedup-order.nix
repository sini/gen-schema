{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) mkIdentityModule;
  mkEval =
    kind: modules:
    genMerge.evalModuleTree {
      modules = [ (mkIdentityModule kind) ] ++ modules;
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
