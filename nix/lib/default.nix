{
  inputs ? { },
  lib,
}:
let
  # No-flakes import: resolve gen from CI template's flake.lock
  lock = builtins.fromJSON (builtins.readFile ../../templates/ci/flake.lock);
  inherit (lock.nodes.gen-algebra) locked;
  genSrc = builtins.fetchTarball {
    url = "https://github.com/${locked.owner}/${locked.repo}/archive/${locked.rev}.zip";
    sha256 = locked.narHash;
  };
  gen = inputs.gen-algebra or (import genSrc { inherit lib; });
  record = gen.pure.record;

  methods = import ./methods.nix { inherit lib; };
  validate = import ./validate.nix { inherit lib gen; };
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
    inherit (refLib) refsFromOptions;
    inherit (mixinLib) applyMixin;
    inherit (bridgeLib) emitModule isOptionDecl;
    inherit (refinedLib) isRefined getRefinements;
  };
  instance = import ./instance.nix {
    inherit lib;
    inherit (gen)
      mkStrictModule
      mkIdentityModule
      runValidators
      defaultOnError
      ;
    inherit (refLib) refsFromOptionsWithTypes dedupByHash;
    inherit (validate) filterValidators;
  };
  docs = import ./docs.nix { inherit lib; };
in
{
  # gen-schema's own exports + validator constructor from gen
  inherit (gen) mkValidator;
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

  _internal = {
    inherit (methods) mkMethodsModule;
  };
}
