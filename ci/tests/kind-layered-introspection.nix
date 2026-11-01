# THE LAYERED INTROSPECTION (den-hoag-f1iza M1-M3) publishes what the full evaluation publishes. Each case of
# `ci/test-fixtures/layered-introspection.nix` reads, cell by cell, the value the a7c9r bundle's head (gen-schema
# 69b1719, gen-merge d20734f: no layering) published, kept as `layered-introspection-expected.json`: chain shapes
# (plain, function-module, mixed, diamond, sealed, nixpkgs-typed, redeclared), the fan over N = 2..4 parents in
# every order, an honest edit of a parent value refused at every composing door (a7c9r v1 gate C1), and one shape
# per predicate conjunct that must send a kind to the full evaluation (a resolver-prefixed def that is not the
# resolver's, a module `key` two sources name, an injected methods module, a function-module parent).
# RED, each read: the parents' planes dropped from the union (every parented shape and fan row); `resolvedBy`
# weakened to the file prefix (`forged`); `key` dropped from gen-merge's `moduleSyntax.closure` (`key`); the
# `injected` conjunct deleted (`methods`); the parents' flag deleted (`fnParent`).
{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  cases = import ../test-fixtures/layered-introspection.nix { inherit lib genSchema genMerge; };
  expected = builtins.fromJSON (
    builtins.readFile ../test-fixtures/layered-introspection-expected.json
  );
in
{
  flake.tests.kind-layered-introspection = lib.mapAttrs' (n: v: {
    name = "test-${n}-publishes-the-full-evaluation";
    value = {
      expr = v;
      expected = expected.${n};
    };
  }) cases;
}
