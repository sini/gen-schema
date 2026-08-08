# Method-generated options are NOT identity keys.
#
# The identity preimage is a kind's option-reflected identity keys minus the declared
# `identity = false` opt-outs — nothing else. A method is declared as an option carrying the
# method's declared type (methods.nix) and its `config` value is the method's RETURN, so a
# primitive-typed method used to satisfy `isPrimitiveOption` and join the preimage. That did not
# merely coarsen identity at the margin: because a method is an arbitrary function of config, a
# method reading an OPTED-OUT field re-admitted that field's value through its return, so the
# declared opt-out stopped being a boundary and DECLARING a method moved an instance's identity.
#
# The three predicates below are that defect stated as an oracle. `control-optout-honoured` is the
# live control: a run in which it fails is an invalid run, not a pass.
{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema)
    mkSchemaOption
    mkInstanceRegistry
    schemaFn
    ;

  # One arm of the fixture: a kind with an opted-out `secret`, optionally read by a
  # primitive-typed method, instantiated once with the given secret value.
  mkArm =
    { withMethod, secretValue }:
    (genMerge.evalModuleTree {
      modules = [
        (
          { config, ... }:
          {
            options.schema = mkSchemaOption { };
            options.hosts = mkInstanceRegistry config.schema.host { };

            config.schema.host = {
              options.secret = genMerge.mkOption { type = genMerge.types.str; } // {
                identity = false;
              };
            }
            // lib.optionalAttrs withMethod {
              methods.leak = schemaFn "reads the opted-out field" genMerge.types.str ({ secret, ... }: secret);
            };

            config.hosts.igloo.secret = secretValue;
          }
        )
      ];
    }).config.hosts.igloo;

  plainA = mkArm {
    withMethod = false;
    secretValue = "s3cret";
  };
  plainB = mkArm {
    withMethod = false;
    secretValue = "different";
  };
  methodA = mkArm {
    withMethod = true;
    secretValue = "s3cret";
  };
  methodB = mkArm {
    withMethod = true;
    secretValue = "different";
  };
in
{
  # CONTROL — without a method, the declared opt-out is honoured: two instances differing only in
  # `secret` mint one identity. This fires in every run; if it stops firing the fixture is broken
  # and the two predicates below say nothing.
  flake.tests.identity-method-optout.test-control-optout-honoured-without-method = {
    expr = plainA.id_hash == plainB.id_hash;
    expected = true;
  };

  # The opt-out survives a method that reads the opted-out field.
  flake.tests.identity-method-optout.test-optout-not-defeated-by-method = {
    expr = methodA.id_hash != methodB.id_hash;
    expected = false;
  };

  # Declaring a method does not move an instance's identity: a method is not an identity key.
  flake.tests.identity-method-optout.test-declaring-a-method-does-not-move-identity = {
    expr = plainA.id_hash != methodA.id_hash;
    expected = false;
  };

  # The method still evaluates — the option is excluded from IDENTITY, not from the instance.
  flake.tests.identity-method-optout.test-control-method-return-still-present = {
    expr = methodA.leak;
    expected = "s3cret";
  };
}
