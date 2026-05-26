{ genAlgebra, lib, ... }:
let
  inherit (genAlgebra) runValidators;

  filterValidators =
    optionNames: validators:
    builtins.filter (
      v: if v ? __fields then builtins.all (f: builtins.elem f optionNames) v.__fields else true
    ) validators;
in
{
  validateInstances =
    schema: kind: instances:
    let
      validators = schema.${kind}.validators or [ ];
    in
    runValidators kind validators instances;

  # Wrap gen-algebra's mkValidator with field requirements.
  # Validators with __fields are skipped when any required field is absent from the kind.
  mkFieldValidator =
    {
      fields,
      name,
      check,
      message,
    }:
    (genAlgebra.mkValidator name check message) // { __fields = fields; };

  # Filter validators by kind's option names.
  # Validators with __fields: skip if any required field is missing from optionNames.
  # Validators without __fields: always included.
  inherit filterValidators;
}
