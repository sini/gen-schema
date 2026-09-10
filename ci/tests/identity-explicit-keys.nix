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

  evalReflected = mkEval "host" [
    {
      options.name = genMerge.mkOption { type = genMerge.types.str; };
      options.role = genMerge.mkOption { type = genMerge.types.str; };
    }
    {
      config.name = "igloo";
      config.role = "web";
    }
  ];
  evalExplicitName = mkEval "host" [
    {
      options.name = genMerge.mkOption { type = genMerge.types.str; };
      options.role = genMerge.mkOption { type = genMerge.types.str; };
    }
    {
      config.name = "igloo";
      config.role = "web";
      config._identity.keys = [ "name" ];
    }
  ];
  evalExplicitNameOnly = mkEval "host" [
    {
      options.name = genMerge.mkOption { type = genMerge.types.str; };
      options.role = genMerge.mkOption { type = genMerge.types.str; };
    }
    {
      config.name = "igloo";
      config.role = "db";
      config._identity.keys = [ "name" ];
    }
  ];
  evalMerged = mkEval "host" [
    {
      options.name = genMerge.mkOption { type = genMerge.types.str; };
      options.role = genMerge.mkOption { type = genMerge.types.str; };
    }
    { config._identity.keys = [ "name" ]; }
    { config._identity.keys = [ "role" ]; }
    {
      config.name = "igloo";
      config.role = "web";
    }
  ];

  # Q4 — the domain an explicit key set is validated against is the CLOSED key set. Two names that
  # are outside it for two different reasons, refused by the one existing message: a name nothing
  # declares, and a name declared with a NON-PRIMITIVE type. The second used to carry its own
  # "is not a primitive type" wording; as far as the kind is concerned it is outside the closed set
  # for one reason, so the refusal needs no second vocabulary and no longer has one.
  keysNaming =
    k:
    mkEval "host" [
      {
        options.name = genMerge.mkOption { type = genMerge.types.str; };
        options.tags = genMerge.mkOption {
          type = genMerge.types.listOf genMerge.types.str;
          default = [ ];
        };
      }
      {
        config.name = "igloo";
        config._identity.keys = [ k ];
      }
    ];
in
{
  flake.tests.identity-explicit.test-explicit-overrides-reflection = {
    expr = evalReflected.config.id_hash == evalExplicitName.config.id_hash;
    expected = false;
  };
  flake.tests.identity-explicit.test-explicit-ignores-other-options = {
    expr = evalExplicitName.config.id_hash == evalExplicitNameOnly.config.id_hash;
    expected = true;
  };
  flake.tests.identity-explicit.test-keys-outside-the-closed-set-are-refused = {
    expr = {
      undeclared = (builtins.tryEval (keysNaming "nosuchoption").config.id_hash).success;
      declaredNonPrimitive = (builtins.tryEval (keysNaming "tags").config.id_hash).success;
      # The arming arm: a name INSIDE the closed set on the same fixture still mints, so the cell
      # above is not passing for a validator that refuses everything.
      control = (builtins.tryEval (keysNaming "name").config.id_hash).success;
    };
    expected = {
      undeclared = false;
      declaredNonPrimitive = false;
      control = true;
    };
  };
  flake.tests.identity-explicit.test-merged-keys = {
    expr = evalMerged.config.id_hash == evalReflected.config.id_hash;
    expected = true;
  };
}
