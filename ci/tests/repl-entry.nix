# THE REPL ENTRY — `ci/repl.nix`, unexercised by every other cell here (which all build the library
# through `../../lib` directly with injected values). Same class `entry.nix` guards for the standalone
# `default.nix` shim: a hand-written formal set can drift from `lib/default.nix`'s and only refuse at
# apply time, where nothing here forces it. Measured 2026-09-11: it named `{ lib, algebra }` while
# `lib/default.nix` takes `{ prelude, merge, algebra, identity }` — an unexpected-argument AND a
# missing-required-argument refusal, uncaught because nothing evaluated it.
#
# Supplying every formal explicitly means the `builtins.getFlake` defaults are never forced, so this
# cell is pure and reaches no network — the same hermeticity `entry.nix` uses for the same reason.
{
  lib,
  genSchema,
  genMerge,
  genAlgebra,
  genIdentity,
  prelude,
  ...
}:
let
  repl = import ../repl.nix {
    inherit lib prelude;
    merge = genMerge;
    algebra = genAlgebra;
    identity = genIdentity;
  };
in
{
  # The ceiling is "it evaluates, and forwards the right values" — not a second copy of the whole
  # library surface. `genSchema`'s own key is asserted alongside its spread contents because the repl
  # keeps it in scope as a bound name, distinct from the exports themselves.
  flake.tests.replEntry.test-repl-entry-loads-with-declared-formals = {
    expr = builtins.sort (a: b: a < b) (builtins.attrNames repl);
    expected = builtins.sort (a: b: a < b) (
      lib.unique (
        [
          "lib"
          "genSchema"
        ]
        ++ builtins.attrNames genSchema
      )
    );
  };
}
