{
  inputs ? { },
  lib,
}:
let
  # No-flakes import: resolve gen from CI template's flake.lock
  lock = builtins.fromJSON (builtins.readFile ../../templates/ci/flake.lock);
  inherit (lock.nodes.gen) locked;
  genSrc = builtins.fetchTarball {
    url = "https://github.com/${locked.owner}/${locked.repo}/archive/${locked.rev}.zip";
    sha256 = locked.narHash;
  };
  gen = inputs.gen or (import genSrc { inherit lib; });

  methods = import ./methods.nix { inherit lib; };
  entryType = import ./entry-type.nix {
    inherit lib;
    inherit (methods) mkMethodsModule;
    inherit (refLib) refsFromOptions;
  };
  validate = import ./validate.nix { inherit lib gen; };
  refinedLib = import ./refined.nix { inherit lib; };
  refLib = import ./ref.nix {
    inherit lib;
    inherit (gen) mkRefType;
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
    inherit (refinedLib) checkRefinements;
  };
  docs = import ./docs.nix { inherit lib; };
  scopeGraph = import ./scope-graph.nix { inherit lib; };
in
{
  # gen-schema's own exports + validator constructor from gen
  inherit (gen) mkValidator;
  inherit (methods) schemaFn;
  inherit (entryType) mkSchemaOption mkSchemaEntryType;
  inherit (instance) mkInstanceType mkInstanceRegistry;
  inherit (validate) validateInstances mkFieldValidator filterValidators;
  inherit (refLib) ref setOf toSet;
  inherit (docs) renderDocs;
  inherit (scopeGraph) buildKindGraph buildInstanceGraph;

  _internal = {
    inherit (methods) mkMethodsModule;
  };
}
