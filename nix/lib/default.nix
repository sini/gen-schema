{ lib }:
let
  strict = import ./strict.nix { inherit lib; };
  identity = import ./identity.nix { inherit lib; };
in
{
  inherit (strict) mkStrictModule;
  inherit (identity) identityModule;
}
