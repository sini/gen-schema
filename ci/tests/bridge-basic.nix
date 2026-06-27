{
  lib,
  genSchema,
  genAlgebra,
  ...
}:
let
  R = genAlgebra.record;
  record = R;
  refinedLib = import ../../lib/refined.nix { inherit lib; };
  bridgeLib = import ../../lib/bridge.nix {
    inherit lib record;
    inherit (refinedLib) isRefined getRefinements;
  };
  inherit (bridgeLib) emitModule isOptionDecl extractRefinements;
  inherit (refinedLib) types;

  # Build a record with mkOption values (option declarations)
  optionRecord = R.fromAttrs {
    port = lib.mkOption {
      type = lib.types.int;
      default = 8080;
    };
    hostname = lib.mkOption { type = lib.types.str; };
  };

  # Record with a mix of options and plain config values
  mixedRecord = R.extend (R.fromAttrs {
    port = lib.mkOption { type = lib.types.int; };
    hostname = lib.mkOption { type = lib.types.str; };
  }) "defaultPort" 8080;

  # Record with refined type
  refinedRecord = R.fromAttrs {
    port = lib.mkOption {
      type = types.refined lib.types.int {
        check = v: v > 0;
        message = "must be positive";
      };
    };
    name = lib.mkOption { type = lib.types.str; };
  };

  # Record with collection labels (validators, methods)
  collectionRecord =
    let
      base = R.fromAttrs {
        port = lib.mkOption { type = lib.types.int; };
        validators = [ "validator-a" ];
      };
    in
    R.extend base "validators" [ "validator-b" ];
in
{
  flake.tests.bridge-basic.test-isOptionDecl-true = {
    expr = isOptionDecl (lib.mkOption { type = lib.types.int; });
    expected = true;
  };

  flake.tests.bridge-basic.test-isOptionDecl-false = {
    expr = isOptionDecl { port = 8080; };
    expected = false;
  };

  flake.tests.bridge-basic.test-emit-options-only = {
    expr =
      let
        result = emitModule [ ] optionRecord;
        eval = lib.evalModules {
          modules = [
            result.module
            {
              config.port = 9090;
              config.hostname = "test";
            }
          ];
        };
      in
      eval.config.port;
    expected = 9090;
  };

  flake.tests.bridge-basic.test-emit-preserves-default = {
    expr =
      let
        result = emitModule [ ] optionRecord;
        eval = lib.evalModules {
          modules = [
            result.module
            { config.hostname = "test"; }
          ];
        };
      in
      eval.config.port;
    expected = 8080;
  };

  flake.tests.bridge-basic.test-emit-mixed-config = {
    expr =
      let
        result = emitModule [ ] mixedRecord;
      in
      result.collections == { } && result.refinements == { };
    expected = true;
  };

  flake.tests.bridge-basic.test-emit-refined-strips-metadata = {
    expr =
      let
        result = emitModule [ ] refinedRecord;
        eval = lib.evalModules {
          modules = [
            result.module
            {
              config.port = 8080;
              config.name = "test";
            }
          ];
        };
      in
      eval.config.port;
    expected = 8080;
  };

  flake.tests.bridge-basic.test-emit-refined-extracts-refinements = {
    expr =
      let
        result = emitModule [ ] refinedRecord;
      in
      builtins.length (result.refinements.port or [ ]);
    expected = 1;
  };

  flake.tests.bridge-basic.test-emit-collection-extraction = {
    expr =
      let
        result = emitModule [ "validators" ] collectionRecord;
      in
      result.collections.validators;
    expected = [
      [ "validator-b" ]
      [ "validator-a" ]
    ];
  };

  flake.tests.bridge-basic.test-emit-collection-not-in-module = {
    expr =
      let
        result = emitModule [ "validators" ] collectionRecord;
        eval = lib.evalModules {
          modules = [
            result.module
            { config.port = 8080; }
          ];
        };
      in
      eval.config ? validators;
    expected = false;
  };
}
