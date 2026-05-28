{ schemaLib, ... }:
let
  tryRegistry = builtins.tryEval (
    schemaLib.mkInstanceRegistry
      {
        kind = "host";
        options = { };
        refs = { };
        strict = true;
      }
      {
        derive = _: { };
        deriveEither = {
          derive = _: { right = { }; };
        };
      }
  );
in
{
  flake.tests."derive-exclusive" = {
    test-throws = {
      expr = tryRegistry.success;
      expected = false;
    };
  };
}
