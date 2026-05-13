{ lib }:
let
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
                  inherit name;
                  validator = v.name;
                  inherit (v) message;
                }
              ]
          ) validators
        ) instances
      );
    in
    if failures == [ ] then { right = instances; } else { left = failures; };

  validateInstances =
    schema: kind: instances:
    let
      validators = schema.${kind}.validators or [ ];
    in
    runValidators kind validators instances;
in
{
  inherit mkValidator runValidators validateInstances;
}
