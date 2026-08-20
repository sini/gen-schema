{
  prelude,
  merge,
  algebra,
  identity,
}:
let
  inherit (algebra) record;

  methods = import ./methods.nix { inherit prelude merge; };
  validate = import ./validate.nix { inherit prelude; };
  # Named for the field it produces, and for the one thing both its bindings agree on. It was
  # `identity.nix` while it contained the mint; it does not, and a file called that beside a
  # LIBRARY called gen-identity is a reader's trap rather than a tidy-up.
  idHashLib = import ./id-hash.nix { inherit prelude merge identity; };
  strictLib = import ./strict.nix { inherit prelude merge; };
  refinedLib = import ./refined.nix { inherit merge; };
  blameLib = import ./blame.nix;
  mixinLib = import ./mixin.nix { inherit record; };
  bridgeLib = import ./bridge.nix {
    inherit prelude record;
    inherit (refinedLib) isRefined getRefinements;
  };
  refLib = import ./ref.nix { inherit prelude merge; };
  # The VALUE-level reference vocabulary, kin to refLib's type-level one — see field-ref.nix's
  # header for the axis that separates them.
  fieldRefLib = import ./field-ref.nix { inherit prelude; };
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
    inherit (idHashLib) mkIdentityModule;
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
  # Identity / strict / validation module surface (gen-schema-owned).
  # ★ `hashIdentity` IS NOT HERE, and its absence is the point. The mint lives in
  # `gen-identity`; re-exporting it under gen-schema's name would re-export its BUILD, which is
  # the verbatim re-handing ADR-0014 rejects — and gen-schema's own discharged instance of that
  # ADR was doing exactly this with gen-merge's seven bindings. A consumer that wants the mint
  # takes the leaf, which it can, because the leaf has no inputs to conflict with anything.
  inherit (idHashLib)
    mkIdentityModule
    identityHashForKind
    ;
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
  inherit (fieldRefLib)
    fieldRef
    isFieldRef
    fieldRefsIn
    fieldRefMarker
    ;
  inherit (refinedLib) refinements checkRefinements;
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
