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
{
  prelude,
  isSchemaKind,
}:
let
  # --- Base constructors (gen-schema-owned) ---

  # ONE REQUIRED RECORD (den-hoag-7gp66 P2, R7(a), the shape of gen-types' own `mkValidator`): the
  # name and the message are both strings, and nothing orders a label, a predicate and its failure
  # text, so they stay one required-argument record, `mkValidator { name; pred; message; }`. The
  # record is a `prelude.door` (open, as a record operand is): a missing field is refused by name
  # and catchably at the application.
  mkValidator =
    prelude.door
      {
        name = "gen-schema.mkValidator";
        required = [
          "name"
          "pred"
          "message"
        ];
        open = true;
      }
      (v: {
        inherit (v) name pred message;
      });

  runValidators =
    kind: validators: instances:
    let
      failures = prelude.concatLists (
        prelude.mapAttrsToList (
          name: instance:
          prelude.concatMap (
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
    prelude.concatMapStringsSep "\n" (
      f: "  ${f.kind} '${f.name}': ${f.validator} — ${f.message}"
    ) failures;

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

  # The kind-value guard is asserted directly in the body (not behind a `kind`
  # binding runValidators may or may not force) so it fires whenever the
  # result is forced at all -- including an empty instance set or an
  # all-passing one, where nothing else would ever demand `kindValue.kind`.
  validateInstances =
    kindValue: instances:
    assert
      isSchemaKind kindValue
      || throw "gen-schema: validateInstances: expected a kind value carrying a mint-backed mark (`__mint.minted`); got an attrset with no mark";
    let
      validators = kindValue.validators or [ ];
    in
    runValidators kindValue.kind validators instances;

  # Wrap mkValidator with field requirements.
  # Validators with __fields are skipped when any required field is absent from the kind.
  #
  # ONE REQUIRED RECORD (den-hoag-7gp66 P2, R7(a), as `mkValidator` above, with the fields the
  # validator requires): all four fields are required, so R5 leaves it open — an extra field is
  # admitted, the stated price of the open-record policy. The record is a `prelude.door`, whose check
  # is forced at the application itself, so a bad record is refused at the door's own WHNF even
  # though the return is an attrset literal.
  mkFieldValidator =
    prelude.door
      {
        name = "gen-schema.mkFieldValidator";
        required = [
          "fields"
          "name"
          "check"
          "message"
        ];
        open = true;
      }
      (v: {
        inherit (v) name message;
        pred = v.check;
        __fields = v.fields;
      });

  # Filter validators by kind's option names.
  # Validators with __fields: skip if any required field is missing from optionNames.
  # Validators without __fields: always included.
  inherit filterValidators;
}
