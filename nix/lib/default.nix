{ lib }:
let
  strict = import ./strict.nix { inherit lib; };
  identity = import ./identity.nix { inherit lib; };
  entryType = import ./entry-type.nix {
    inherit lib;
    inherit (strict) mkStrictModule;
    inherit (identity) identityModule;
  };
  instance = import ./instance.nix { inherit lib; };
in
{
  inherit (strict) mkStrictModule;
  inherit (identity) identityModule;
  inherit (entryType) mkSchema mkSchemaEntryType;
  inherit (instance) mkInstanceType mkInstanceRegistry;
}
