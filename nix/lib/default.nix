{ lib }:
let
  strict = import ./strict.nix { inherit lib; };
  identity = import ./identity.nix { inherit lib; };
  entryType = import ./entry-type.nix {
    inherit lib;
    inherit (strict) mkStrictModule;
    inherit (identity) identityModule;
  };
in
{
  inherit (strict) mkStrictModule;
  inherit (identity) identityModule;
  inherit (entryType) mkSchema mkSchemaEntryType;
}
