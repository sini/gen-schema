{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  schema = genSchema.evalSchema { } [
    {
      config.schema.host = {
        options.addr = genMerge.mkOption { type = genMerge.types.str; };
      };
    }
  ];

  eval = genMerge.evalModuleTree { } [
    {
      options.hosts = genSchema.mkInstanceRegistry {
        deriveEither = {
          derive = _instances: { left = "something went wrong"; };
        };
      } schema.host;
      config.hosts.igloo.addr = "10.0.1.1";
    }
  ];
in
{
  flake.tests."derive-either-left" = {
    test-throws-on-left = {
      expr =
        (builtins.tryEval (builtins.deepSeq eval.config.hosts.igloo.addr eval.config.hosts.igloo.addr))
        .success;
      expected = false;
    };
    # den-hoag-2vo1m: the derive failure is refused at the ELEMENT read above; the name set is the
    # definitions', so a name read answers it without running `derive`.
    test-the-name-set-is-the-definitions = {
      expr = builtins.attrNames eval.config.hosts;
      expected = [ "igloo" ];
    };
  };
}
