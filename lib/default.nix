{
  prelude,
  merge,
  algebra,
}:
let
  inherit (algebra) record;

  methods = import ./methods.nix { inherit prelude merge; };
  validate = import ./validate.nix { inherit prelude; };
  identityLib = import ./identity.nix { inherit prelude merge; };
  strictLib = import ./strict.nix { inherit prelude merge; };
  refinedLib = import ./refined.nix;
  blameLib = import ./blame.nix;
  mixinLib = import ./mixin.nix { inherit record; };
  bridgeLib = import ./bridge.nix {
    inherit prelude record;
    inherit (refinedLib) isRefined getRefinements;
  };
  refLib = import ./ref.nix { inherit prelude merge; };
  entryType = import ./entry-type.nix {
    inherit prelude merge record;
    inherit (methods) mkMethodsModule;
    inherit (refLib) refsFromOptionsWithTypes;
    inherit (mixinLib) applyMixin;
    inherit (bridgeLib) emitModule isOptionDecl;
    inherit (refinedLib) getRefinements;
  };
  instance = import ./instance.nix {
    inherit prelude merge;
    inherit (strictLib) mkStrictModule;
    inherit (identityLib) mkIdentityModule;
    inherit (validate)
      runValidators
      defaultOnError
      filterValidators
      ;
    inherit (refLib) dedupByHash;
  };
  docs = import ./docs.nix { inherit prelude; };
  codecLib = import ./codec.nix { inherit prelude; };
in
{
  # Module-system constructors, re-exported from gen-merge so consumers (den
  # entities are gen-schema registries) never reach for nixpkgs `lib`.
  inherit (merge)
    mkOption
    mkOptionType
    mkMerge
    mkDefault
    mkForce
    evalModuleTree
    ;
  inherit (merge) types;

  # Identity / strict / validation module surface (gen-schema-owned).
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
