{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) mkIdentityModule identityKeysForKind identityHashForKind;
  # The door takes the KIND DECLARATION, never its name. `mkEval kind modules`: the HEAD of the list
  # is the kind's declarations, evaluated through `evalSchema` as the kind `kind`; the TAIL is the
  # instance's definitions. See ci/tests/identity-hash.nix for the full note, including why a cell
  # comparing two DECLARATIONS recomputes under one kind rather than comparing two stamps.
  mkKind =
    kind: decl:
    (genSchema.evalSchema {
      modules = [ { config.schema.${kind} = decl; } ];
    }).${kind};
  mkEval =
    kind: modules:
    let
      kindValue = mkKind kind (builtins.head modules);
    in
    genMerge.evalModuleTree {
      modules = [ (mkIdentityModule kindValue (identityKeysForKind { } kindValue)) ] ++ modules;
    }
    // {
      inherit kindValue;
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
  # An opted-out option does not enter the identity CONTENT. The kind with `secret` and the kind
  # without it are two declarations, so their stamps differ whatever the keys are; the property is
  # that the with-secret instance, recomputed under the name-only kind, is the name-only instance,
  # and that the two kinds close over one key set.
  flake.tests.identity-optout.test-identity-false-matches-without = {
    expr = {
      contentUnderNameOnlyKind =
        identityHashForKind evalNameOnly.kindValue evalWithSecret.config == evalNameOnly.config.id_hash;
      keySetsEqual =
        identityKeysForKind { } evalWithSecret.kindValue == identityKeysForKind { } evalNameOnly.kindValue;
    };
    expected = {
      contentUnderNameOnlyKind = true;
      keySetsEqual = true;
    };
  };
  # `internal` is presentation only: it hides an option from generated docs and never excludes it
  # from identity. Among primitive options `identity = false` is the one exclusion channel. Judged
  # on the KEY plane: two declarations' stamps differ whatever their keys are, so a stamp
  # inequality here would hold even with `internal_val` excluded.
  flake.tests.identity-optout.test-internal-reflected = {
    expr =
      identityKeysForKind { } evalWithInternal.kindValue
      == identityKeysForKind { } evalNameOnly.kindValue;
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
