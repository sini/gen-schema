# gen-schema REPL — all exports in scope.
let
  nixpkgs = import (builtins.getFlake "nixpkgs") { };
  inherit (nixpkgs) lib;
  algebra = (builtins.getFlake "github:sini/gen-algebra").lib;
  genSchema = import ../lib { inherit lib algebra; };
in
{ inherit lib genSchema; } // genSchema
