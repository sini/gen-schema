{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) mkIdentityModule identityKeysForKind;
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
