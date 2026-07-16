# Purity invariant (C3 re-host): the gen-schema library (./lib) is nixpkgs-lib-free. The registry
# ENGINE drives on gen-merge's byte-mode `evalModuleTree` + gen-types leaf checkers, so it must never
# CALL `lib.evalModules` / `lib.types` / `lib.mkOption` nor pull `nixpkgs`. A stray tether in the
# library source (or the root flake.nix / default.nix) fails CI.
#
# NB gen-schema legitimately RE-EXPORTS `mkOption`/`mkOptionType`/`mkMerge`/`evalModuleTree` (from
# gen-merge — the nixpkgs replacements), so those bare names are NOT forbidden; only the nixpkgs
# `lib.`-tether is. `evalModules` is safe to forbid — it is not an infix of `evalModuleTree`.
#
# Scope: lib/**.nix + the root flake.nix + default.nix. NOT ci/ (the harness legitimately uses
# nixpkgs.lib, and the test corpus still uses `lib.*` for non-schema assertions).
{ genPrelude, lib, ... }:
let
  libDir = ../../lib;

  stripComments =
    text:
    lib.concatStringsSep "\n" (
      map (line: lib.head (lib.splitString "#" line)) (lib.splitString "\n" text)
    );

  walk =
    dir:
    lib.concatLists (
      lib.mapAttrsToList (
        name: type:
        if type == "directory" then
          walk (dir + "/${name}")
        else if lib.hasSuffix ".nix" name then
          [ (dir + "/${name}") ]
        else
          [ ]
      ) (builtins.readDir dir)
    );

  sources =
    map (p: {
      name = toString p;
      code = stripComments (builtins.readFile p);
    }) (walk libDir)
    ++
      map
        (rel: {
          name = rel;
          code = stripComments (builtins.readFile (../.. + "/${rel}"));
        })
        [
          "flake.nix"
          "default.nix"
        ];

  # The nixpkgs / module-system tether. gen-schema's own re-exported API names are absent.
  forbidden = [
    "nixpkgs"
    "lib.types"
    "lib.mkOption"
    "lib.mkMerge"
    "lib.evalModules"
    "evalModules"
    "{ lib }"
    "{ lib,"
  ];

  violations = lib.concatMap (
    src:
    map (tok: "${src.name}: '${tok}'") (lib.filter (tok: genPrelude.hasInfix tok src.code) forbidden)
  ) sources;
in
{
  flake.tests.purity.test-library-source-is-nixpkgs-free = {
    expr = violations;
    expected = [ ];
  };
}
