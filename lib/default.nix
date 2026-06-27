{
  lib,
  algebra,
}:
let
  record = algebra.record;

  methods = import ./methods.nix { inherit lib; };
  validate = import ./validate.nix { inherit lib; };
  identityLib = import ./identity.nix { inherit lib; };
  strictLib = import ./strict.nix { inherit lib; };
  refinedLib = import ./refined.nix { inherit lib; };
  blameLib = import ./blame.nix { inherit lib; };
  mixinLib = import ./mixin.nix { inherit lib record; };
  bridgeLib = import ./bridge.nix {
    inherit lib record;
    inherit (refinedLib) isRefined getRefinements;
  };
  refLib = import ./ref.nix { inherit lib; };
  entryType = import ./entry-type.nix {
    inherit lib record;
    inherit (methods) mkMethodsModule;
    inherit (refLib) refsFromOptionsWithTypes;
    inherit (mixinLib) applyMixin;
    inherit (bridgeLib) emitModule isOptionDecl;
    inherit (refinedLib) isRefined getRefinements;
  };
  instance = import ./instance.nix {
    inherit lib;
    inherit (strictLib) mkStrictModule;
    inherit (identityLib) mkIdentityModule;
    inherit (validate)
      runValidators
      defaultOnError
      filterValidators
      ;
    inherit (refLib) dedupByHash;
  };
  docs = import ./docs.nix { inherit lib; };
  codecLib = import ./codec.nix { inherit lib; };
in
{
  # Module-system constructors (gen-schema-owned; relocated from gen-algebra).
  inherit (identityLib) mkIdentityModule;
  inherit (strictLib) mkStrictModule;
  inherit (validate)
    mkValidator
    runValidators
    formatErrors
    defaultOnError
    ;
  inherit (methods) schemaFn;
  inherit (entryType) mkSchemaOption mkSchemaEntryType;
  inherit (instance) mkInstanceType mkInstanceRegistry;
  inherit (validate) validateInstances mkFieldValidator filterValidators;
  inherit (refLib) ref setOf toSet;
  inherit (refinedLib) refinements;
  inherit (refinedLib.types) refined;
  inherit (blameLib) blame;
  inherit (mixinLib)
    mkMixin
    composeMixins
    beta
    applyMixin
    ;
  inherit (bridgeLib) emitModule;
  inherit (docs) renderDocs;
  inherit (codecLib) mkCodec;

  _internal = {
    inherit (methods) mkMethodsModule;
  };
}
