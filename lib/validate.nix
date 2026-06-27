# Validators — named predicate contracts over a kind's instances.
#
# Base constructors (mkValidator/runValidators/formatErrors/defaultOnError) plus
# gen-schema's field-aware wrappers (mkFieldValidator/filterValidators) and the
# kind-driven entry point (validateInstances). A validator is a plain record
# { name; pred; message; } evaluated against every instance of a kind; failures
# collect into an Either ({ right = instances; } | { left = [failure]; }).
#
# Base constructors relocated from gen-algebra/module so gen-schema owns its full
# module-system surface; gen-algebra is the pure algebra root.
{ lib, ... }:
let
  # --- Base constructors (gen-schema-owned) ---

  mkValidator = name: pred: message: {
    inherit name pred message;
  };

  runValidators =
    kind: validators: instances:
    let
      failures = lib.concatLists (
        lib.mapAttrsToList (
          name: instance:
          lib.concatMap (
            v:
            if v.pred instance then
              [ ]
            else
              [
                {
                  inherit kind name;
                  validator = v.name;
                  inherit (v) message;
                }
              ]
          ) validators
        ) instances
      );
    in
    if failures == [ ] then { right = instances; } else { left = failures; };

  formatErrors =
    failures:
    lib.concatMapStringsSep "\n" (f: "  ${f.kind} '${f.name}': ${f.validator} — ${f.message}") failures;

  defaultOnError =
    left:
    if builtins.isList left then
      throw "schema validation failed:\n${formatErrors left}"
    else
      throw "gen-schema: unexpected validation error: ${builtins.toJSON left}";

  # --- Field-aware wrappers ---

  filterValidators =
    optionNames: validators:
    builtins.filter (
      v: if v ? __fields then builtins.all (f: builtins.elem f optionNames) v.__fields else true
    ) validators;
in
{
  inherit
    mkValidator
    runValidators
    formatErrors
    defaultOnError
    ;

  validateInstances =
    kindValue: instances:
    let
      _guard =
        assert
          (kindValue ? kind && kindValue ? options)
          || throw "gen-schema: validateInstances: expected a kind value (e.g., schema.host), got an attrset without 'kind' or 'options'";
        null;
      validators = kindValue.validators or [ ];
    in
    runValidators (builtins.seq _guard kindValue.kind) validators instances;

  # Wrap mkValidator with field requirements.
  # Validators with __fields are skipped when any required field is absent from the kind.
  mkFieldValidator =
    {
      fields,
      name,
      check,
      message,
    }:
    (mkValidator name check message) // { __fields = fields; };

  # Filter validators by kind's option names.
  # Validators with __fields: skip if any required field is missing from optionNames.
  # Validators without __fields: always included.
  inherit filterValidators;
}
