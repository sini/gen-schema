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
        (mkIdentityModule kind (
          identityKeysForKind { } {
            imports = modules;
          }
        ))
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

  # A kind declaring `name` plus the option under test as `rk`; `differs` asks whether two
  # instances differing only in `rk` mint distinct identities, i.e. whether `rk` is a key.
  rkDecl = args: extra: {
    options.name = genMerge.mkOption { type = genMerge.types.str; };
    options.rk = genMerge.mkOption ({ type = genMerge.types.str; } // args) // extra;
  };
  evalRk =
    args: extra: value:
    mkEval "host" [
      (rkDecl args extra)
      {
        config.name = "igloo";
        config.rk = value;
      }
    ];
  differs =
    args: extra: (evalRk args extra "r1").config.id_hash != (evalRk args extra "r2").config.id_hash;
  internalArgs = {
    internal = true;
    readOnly = true;
  };
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
  # `internal` is presentation only: it hides an option from generated docs and never excludes it
  # from identity. Among primitive options `identity = false` is the one exclusion channel.
  flake.tests.identity-optout.test-internal-reflected = {
    expr = evalWithInternal.config.id_hash == evalNameOnly.config.id_hash;
    expected = false;
  };
  # A system-owned field — internal and readOnly — is an identity key by reflection.
  flake.tests.identity-optout.test-internal-readonly-is-key = {
    expr = differs internalArgs { };
    expected = true;
  };
  flake.tests.identity-optout.test-internal-readonly-in-key-set = {
    expr = identityKeysForKind { } (rkDecl internalArgs { });
    expected = [
      "name"
      "rk"
    ];
  };
  # `identity = true` adds nothing: the key is already reflected.
  flake.tests.identity-optout.test-identity-true-inert = {
    expr = differs internalArgs { identity = true; };
    expected = true;
  };
  # The declared opt-out still excludes an internal option.
  flake.tests.identity-optout.test-internal-identity-false-excluded = {
    expr = differs internalArgs { identity = false; };
    expected = false;
  };
  # `visible` is not an identity input either.
  flake.tests.identity-optout.test-visible-false-is-key = {
    expr = differs { visible = false; } { };
    expected = true;
  };
}
