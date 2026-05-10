{ lib }:
let
  strict = import ./strict.nix { inherit lib; };
in
{
  inherit (strict) mkStrictModule;
}
