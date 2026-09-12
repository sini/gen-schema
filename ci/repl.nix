# gen-schema REPL — all exports in scope. `nix repl ci/repl.nix` auto-applies a top-level function
# to its defaults, so this fetches the four `lib/default.nix` formals from the flake registry; pass
# an override (e.g. a local checkout) to swap one in.
{
  lib ? (import (builtins.getFlake "nixpkgs") { }).lib,
  prelude ? (builtins.getFlake "github:sini/gen-prelude").lib,
  merge ? (builtins.getFlake "github:sini/gen-merge").lib,
  algebra ? (builtins.getFlake "github:sini/gen-algebra").lib,
  identity ? (builtins.getFlake "github:sini/gen-identity").lib,
}:
let
  genSchema = import ../lib {
    inherit
      prelude
      merge
      algebra
      identity
      ;
  };
in
{ inherit lib genSchema; } // genSchema
