{ lib, schemaLib, ... }:
let
  tryRegistry = builtins.tryEval (
    schemaLib.mkInstanceRegistry
      {
        host = {
          options = { };
        };
      }
      "host"
      {
        derive = _: { };
        deriveEither = {
          derive = _: { right = { }; };
        };
      }
  );
in
{
  "derive-exclusive" = {
    test-throws = {
      expr = tryRegistry.success;
      expected = false;
    };
  };
}
