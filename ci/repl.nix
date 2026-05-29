# gen-schema REPL — all exports in scope.
let
  nixpkgs = import (builtins.getFlake "nixpkgs") { };
  inherit (nixpkgs) lib;
  genSchema = import ../nix/lib { inherit lib; };
in
{ inherit lib genSchema; } // genSchema
