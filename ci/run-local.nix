# Local test runner (the C3 re-host GATE).
#
# The flake `ci` can't resolve the unpublished gen-* deps yet, so this drives the whole
# ci/tests corpus against the LOCAL worktrees of gen-prelude/gen-types/gen-merge/gen-algebra
# plus this worktree's ./lib. nixpkgs.lib is pulled ONLY for the harness side (assertions
# and any non-schema `lib.*` the tests still use).
#
#   nix eval --impure --json -f ci/run-local.nix
#
# → { total; passed; failures = [ "suite.name" … ]; }   (failures MUST be [ ]).
let
  prelude = import /home/sini/Documents/repos/gen-prelude/lib;
  genTypes = import /home/sini/Documents/repos/gen-types/lib { inherit prelude; };
  genMerge = import /home/sini/Documents/repos/gen-merge/lib {
    inherit prelude;
    types = genTypes;
  };
  genAlgebra = import /home/sini/Documents/repos/gen-algebra/lib;
  genSchema = import ../lib {
    inherit prelude;
    merge = genMerge;
    algebra = genAlgebra;
  };
  lib = (builtins.getFlake "nixpkgs").lib;

  specialArgs = {
    inherit
      genSchema
      genMerge
      genTypes
      genAlgebra
      prelude
      lib
      ;
  };

  # ── discover ci/tests/*.nix ──
  testDir = ./tests;
  testFiles = builtins.filter (n: lib.hasSuffix ".nix" n) (
    builtins.attrNames (builtins.readDir testDir)
  );

  # ── collect { suite.name = { expr; expected; } } leaves from each file's flake.tests ──
  # A leaf is any attrset carrying both `expr` and `expected`; suites nest one level under
  # flake.tests, but we recurse defensively.
  collectLeaves =
    prefix: attrs:
    lib.concatLists (
      lib.mapAttrsToList (
        name: v:
        let
          path = if prefix == "" then name else "${prefix}.${name}";
        in
        if builtins.isAttrs v && v ? expr && v ? expected then
          [
            {
              name = path;
              inherit (v) expr expected;
            }
          ]
        else if builtins.isAttrs v then
          collectLeaves path v
        else
          [ ]
      ) attrs
    );

  perFile =
    fileName:
    let
      imported = import (testDir + "/${fileName}") specialArgs;
      tests = imported.flake.tests or { };
    in
    collectLeaves "" tests;

  cases = lib.concatMap perFile testFiles;

  results = map (
    tc:
    let
      e = builtins.tryEval (builtins.deepSeq tc.expr (tc.expr == tc.expected));
    in
    {
      inherit (tc) name;
      pass = e.success && e.value;
    }
  ) cases;

  failures = map (r: r.name) (builtins.filter (r: !r.pass) results);
in
{
  total = builtins.length results;
  passed = builtins.length (builtins.filter (r: r.pass) results);
  inherit failures;
}
