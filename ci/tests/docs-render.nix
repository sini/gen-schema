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

  # den-hoag-p2ld: docs.nix used to drop any field named with a leading underscore,
  # regardless of whether it was actually marked `internal`. A user-declared field
  # that merely happens to start with `_` must render like any other field — only
  # the `internal` flag (and the always-excluded `id_hash`) may exclude it.
  underscoreFieldEval = genMerge.evalModuleTree {
    modules = [
      {
        options.schema = mkSchemaOption { };
        config.schema.device = {
          options._legacyId = genMerge.mkOption {
            type = genMerge.types.str;
            description = "Legacy id — not module-internal, just underscore-named";
          };
        };
      }
    ];
  };
  renderedUnderscoreField = renderDocs underscoreFieldEval.config.schema;

  # A reserved kind name must fail renderDocs the SAME way it fails plain schema
  # evaluation — no silently-partial doc, since renderDocs reads _kindNames itself.
  reservedEval = genMerge.evalModuleTree {
    modules = [
      {
        options.schema = mkSchemaOption { };
        config.schema._hidden = {
          options.secret = genMerge.mkOption { type = genMerge.types.str; };
        };
      }
    ];
  };
  renderDocsReservedAttempt = builtins.tryEval (
    builtins.deepSeq (renderDocs reservedEval.config.schema) (renderDocs reservedEval.config.schema)
  );
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
  flake.tests.docs.test-underscore-field-not-dropped-when-not-internal = {
    expr = lib.hasInfix "_legacyId" renderedUnderscoreField;
    expected = true;
  };
  flake.tests.docs.test-renderDocs-consistent-with-reserved-kind-throw = {
    expr = renderDocsReservedAttempt.success;
    expected = false;
  };
}
