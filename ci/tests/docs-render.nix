{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) mkSchemaOption renderDocs schemaFn;

  eval = genMerge.evalModuleTree {
    modules = [
      {
        options.schema = mkSchemaOption { };
        config.schema.host = {
          options.name = genMerge.mkOption {
            type = genMerge.types.str;
            description = "Hostname";
          };
          options.addr = genMerge.mkOption {
            type = genMerge.types.str;
            description = "IP address";
          };
          methods.greeting = schemaFn "Greeting message" genMerge.types.str ({ name, ... }: "hi ${name}");
        };
      }
    ];
  };

  rendered = renderDocs eval.config.schema;
in
{
  flake.tests.docs.test-contains-kind-heading = {
    expr = lib.hasInfix "## host" rendered;
    expected = true;
  };
  flake.tests.docs.test-contains-option-name = {
    expr = lib.hasInfix "name" rendered;
    expected = true;
  };
  flake.tests.docs.test-contains-table-header = {
    expr = lib.hasInfix "| Option | Type |" rendered;
    expected = true;
  };
  flake.tests.docs.test-is-string = {
    expr = builtins.isString rendered;
    expected = true;
  };
  # A method is derived/computed, never a declared field — mkCodec already drops it
  # (ci/tests/codec-basic.nix: test-encode-strips-methods). Docs must agree: a method
  # is not an option row, matching the shared `internal` marker id-hash.nix's
  # isPrimitiveOption reads for the same exclusion.
  flake.tests.docs.test-excludes-method-row = {
    expr = lib.hasInfix "greeting" rendered;
    expected = false;
  };
}
