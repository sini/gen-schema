{ gen, ... }:
let
  inherit (gen) runValidators;
in
{
  validateInstances =
    schema: kind: instances:
    let
      validators = schema.${kind}.validators or [ ];
    in
    runValidators kind validators instances;
}
