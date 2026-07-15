# keySemantics is opaque introspectable metadata — gen-schema records it
# verbatim on the emitted schema entry and assigns it no meaning. category
# is just a string it threads; a later library (gen-aspects) interprets it.
{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) mkSchemaOption;

  semantics = {
    nixos = {
      category = "class";
    };
    firewall = {
      category = "channel";
    };
  };

  eval = genMerge.evalModuleTree {
    modules = [
      {
        options.schema = mkSchemaOption { keySemantics = semantics; };
        config.schema.host = {
          options.name = genMerge.mkOption { type = genMerge.types.str; };
        };
      }
    ];
  };

  # Default: no keySemantics passed → recorded as {}
  evalDefault = genMerge.evalModuleTree {
    modules = [
      {
        options.schema = mkSchemaOption { };
        config.schema.host = {
          options.name = genMerge.mkOption { type = genMerge.types.str; };
        };
      }
    ];
  };
in
{
  flake.tests.key-semantics.test-keysemantics-recorded = {
    expr = eval.config.schema.host.keySemantics;
    expected = semantics;
  };
  flake.tests.key-semantics.test-keysemantics-default-empty = {
    expr = evalDefault.config.schema.host.keySemantics;
    expected = { };
  };
}
