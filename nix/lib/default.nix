{ lib }:
let
  strict = import ./strict.nix { inherit lib; };
  identity = import ./identity.nix { inherit lib; };
  methods = import ./methods.nix { inherit lib; };
  entryType = import ./entry-type.nix {
    inherit lib;
    inherit (methods) mkMethodsModule;
  };
  instance = import ./instance.nix {
    inherit lib;
    inherit (strict) mkStrictModule;
    inherit (identity) mkIdentityModule;
    inherit (validate) runValidators;
  };
  validate = import ./validate.nix { inherit lib; };
  refType = import ./ref-type.nix { inherit lib; };
  docs = import ./docs.nix { inherit lib; };
in
{
  # Public API
  inherit (methods) schemaFn;
  inherit (entryType) mkSchemaOption mkSchemaEntryType;
  inherit (instance) mkInstanceType mkInstanceRegistry;
  inherit (validate) mkValidator validateInstances;
  inherit (refType) mkRefType;
  inherit (docs) renderDocs;

  # Internals — accessible for testing and advanced use, not public API contract
  _internal = {
    inherit (strict) mkStrictModule;
    inherit (identity) mkIdentityModule;
    inherit (methods) mkMethodsModule;
    inherit (validate) runValidators;
  };
}
