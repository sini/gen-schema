# Module bridge (§ Cardelli 1997).
# Translates record-algebra records into gen-merge modules.
# One-directional: algebra → modules. Information does not flow back.
{
  prelude,
  record,
  isRefined,
  getRefinements,
}:
let
  # NixOS option declarations have _type = "option"
  isOptionDecl = v: builtins.isAttrs v && v ? _type && v._type == "option";

  # Strip refinement metadata from a type, returning the base NixOS type
  stripRefinements = type: if isRefined type then type.__schema.baseType else type;

  # Extract refinement metadata from option declarations
  # Returns { fieldName = [refinements]; } for refined fields
  extractRefinements =
    attrs:
    prelude.filterAttrs (_: v: v != [ ]) (
      prelude.mapAttrs (
        _: v: if isOptionDecl v && v ? type && v.type ? __schema then getRefinements v.type else [ ]
      ) attrs
    );

  # Emit a record-algebra record as a NixOS module
  # collectionLabels: which labels to extract with full stacks
  emitModule =
    collectionLabels: record':
    let
      allAttrs = record.emitAll record' collectionLabels;
      collections = prelude.filterAttrs (n: _: builtins.elem n collectionLabels) allAttrs;
      content = builtins.removeAttrs allAttrs collectionLabels;

      options = prelude.filterAttrs (_: isOptionDecl) content;
      config = builtins.removeAttrs content (builtins.attrNames options);

      strippedOptions = prelude.mapAttrs (
        _: opt:
        if opt ? type && opt.type ? __schema then opt // { type = stripRefinements opt.type; } else opt
      ) options;

      refinements = extractRefinements content;
    in
    {
      module =
        { ... }:
        {
          options = strippedOptions;
          config = config;
        };
      inherit collections refinements;
    };
in
{
  inherit emitModule isOptionDecl;
}
