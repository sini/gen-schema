{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) mkIdentityModule identityKeysForKind;
  # One module list plays both parts — the kind whose own evaluation closes the key set, and the
  # modules imported beside the identity module. See ci/tests/identity-hash.nix for the full note.
  mkEval =
    kind: modules:
    genMerge.evalModuleTree {
      modules = [
        (mkIdentityModule kind (identityKeysForKind {
          imports = modules;
        }))
      ]
      ++ modules;
    };

  evalWithSecret = mkEval "host" [
    {
      options.name = genMerge.mkOption { type = genMerge.types.str; };
      options.secret = genMerge.mkOption { type = genMerge.types.str; } // {
        identity = false;
      };
    }
    {
      config.name = "igloo";
      config.secret = "s3cret";
    }
  ];
  evalWithDiffSecret = mkEval "host" [
    {
      options.name = genMerge.mkOption { type = genMerge.types.str; };
      options.secret = genMerge.mkOption { type = genMerge.types.str; } // {
        identity = false;
      };
    }
    {
      config.name = "igloo";
      config.secret = "different";
    }
  ];
  evalNameOnly = mkEval "host" [
    { options.name = genMerge.mkOption { type = genMerge.types.str; }; }
    { config.name = "igloo"; }
  ];
  evalWithInternal = mkEval "host" [
    {
      options.name = genMerge.mkOption { type = genMerge.types.str; };
      options.internal_val = genMerge.mkOption {
        type = genMerge.types.str;
        internal = true;
      };
    }
    {
      config.name = "igloo";
      config.internal_val = "hidden";
    }
  ];
in
{
  flake.tests.identity-optout.test-identity-false-excluded = {
    expr = evalWithSecret.config.id_hash == evalWithDiffSecret.config.id_hash;
    expected = true;
  };
  flake.tests.identity-optout.test-identity-false-matches-without = {
    expr = evalWithSecret.config.id_hash == evalNameOnly.config.id_hash;
    expected = true;
  };
  flake.tests.identity-optout.test-internal-excluded = {
    expr = evalWithInternal.config.id_hash == evalNameOnly.config.id_hash;
    expected = true;
  };
}
