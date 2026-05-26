# gen-schema REPL — all exports in scope.
let
  nixpkgs = import (builtins.getFlake "nixpkgs") { };
  inherit (nixpkgs) lib;
  schemaLib = import ../nix/lib { inherit lib; };
in
{ inherit lib schemaLib; } // schemaLib
