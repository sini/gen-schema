{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) mkSchemaOption;

  eval = genMerge.evalModuleTree {
    modules = [
      {
        options.schema = mkSchemaOption { };
        config.schema.host = {
          options.name = genMerge.mkOption { type = genMerge.types.str; };
        };
        config.schema.user = {
          options.userName = genMerge.mkOption { type = genMerge.types.str; };
        };
      }
    ];
  };

  # den-hoag-p2ld: a kind declared with a leading underscore used to fully evaluate
  # (config.schema._hidden.kind == "_hidden") while silently vanishing from _kindNames
  # and _topology — an absence-collapse. The `_` prefix is reserved by README
  # convention; the fix enforces that reservation by throwing at declaration instead
  # of silently dropping the name from the introspection surfaces.
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
  reservedKindNamesAttempt = builtins.tryEval (
    builtins.deepSeq reservedEval.config.schema._kindNames reservedEval.config.schema._kindNames
  );
in
{
  # Control: an ordinary, unprefixed kind is present in _kindNames.
  flake.tests.introspect-names.test-control-kind-names = {
    expr = eval.config.schema._kindNames;
    expected = [
      "host"
      "user"
    ];
  };
  # The submodule's own declared introspection options must never be mistaken for
  # user kinds, discriminated by their `internal = true` flag (not a name prefix).
  flake.tests.introspect-names.test-internal-fields-excluded-from-kindNames = {
    expr = builtins.all (n: !(builtins.elem n eval.config.schema._kindNames)) [
      "_kindNames"
      "_topology"
      "_refEdges"
      "_edges"
      "_roots"
      "_leaves"
      "_collectionKeys"
    ];
    expected = true;
  };
  flake.tests.introspect-names.test-underscore-kind-name-throws = {
    expr = reservedKindNamesAttempt.success;
    expected = false;
  };
}
