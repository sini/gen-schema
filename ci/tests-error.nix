# THE SECOND TEST OUTPUT — cells whose subject is WHICH refusal fired, not that one did.
#
# `builtins.tryEval` answers `{ success = false; value = false; }` and discards the message, so every
# `.success == false` cell under ./tests pins that a refusal happened and nothing about what it said.
# Both cells below exist because a message that misdiagnoses passes such a cell perfectly: the
# `_identity.keys` refusal spent this build's first round telling a caller that a declared option was
# undeclared, and the Q4 cell that covers that input stayed green throughout.
#
# ★ WHY A SECOND OUTPUT RATHER THAN A SECOND SUITE. `gen-harness.lib.mkCi` builds `checks.default`
# from an asserter that evaluates `t.expr == t.expected` UNCONDITIONALLY and quantifies over
# `config.flake.tests` and nothing else. A cell with no `expected` and a throwing `expr` therefore
# CRASHES that batch gate rather than failing it. Hosting these on `flake.testsError` puts them
# outside the asserter's quantifier while keeping them live on the nix-unit path — the wiring
# gen-merge and gen-memo already carry, reached through `mkCi`'s `extraModules`.
#
#   nix-unit --flake ./ci#tests        # the suites
#   nix-unit --flake ./ci#testsError   # these cells
{
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) mkIdentityModule identityKeysForKind;

  # A kind declaring one primitive identity key and one option that is DECLARED but not an identity
  # key. `tags` is the input P3 was measured on: it is declared, so "is not declared" was a lie.
  hostModules = [
    {
      options.name = genMerge.mkOption { type = genMerge.types.str; };
      options.role = genMerge.mkOption { type = genMerge.types.str; };
      options.tags = genMerge.mkOption {
        type = genMerge.types.listOf genMerge.types.str;
        default = [ ];
      };
    }
    {
      config.name = "igloo";
      config.role = "web";
    }
  ];

  keysNaming =
    k:
    (genMerge.evalModuleTree {
      modules = [
        (mkIdentityModule "host" (identityKeysForKind {
          imports = hostModules;
        }))
      ]
      ++ hostModules
      ++ [ { config._identity.keys = [ k ]; } ];
    }).config.id_hash;
in
{
  flake.testsError.identity-refusals = {
    # P3, on the input that made the predecessor false. `tags` IS declared on this kind, so the
    # message may not say it is not; it names membership and prints the set instead.
    test-explicit-key-declared-but-not-an-identity-key-names-membership = {
      expr = keysNaming "tags";
      expectedError = {
        type = "ThrownError";
        msg = "^_identity\\.keys: 'tags' is not an identity key of kind 'host' \\(identity keys: name, role\\)$";
      };
    };

    # The same wording on a name nothing declares. One message, both arms — which is the whole point
    # of naming membership rather than a cause.
    test-explicit-key-undeclared-names-the-same-membership = {
      expr = keysNaming "nosuchoption";
      expectedError = {
        type = "ThrownError";
        msg = "^_identity\\.keys: 'nosuchoption' is not an identity key of kind 'host' \\(identity keys: name, role\\)$";
      };
    };

    # P1. `name` is RESERVED, not declared: the key set prepends it unconditionally, and
    # `mkInstanceType` is what declares it. A caller reaching `mkIdentityModule` directly is the one
    # party that can hand over an instance without it, and it used to die on a raw
    # `attribute 'name' missing` naming a line in `lib/id-hash.nix`.
    test-reserved-name-undeclared-refuses-by-name = {
      expr =
        let
          noName = [
            {
              options.load = genMerge.mkOption {
                type = genMerge.types.str;
                default = "x";
              };
            }
          ];
        in
        (genMerge.evalModuleTree {
          modules = [
            (mkIdentityModule "host" (identityKeysForKind {
              imports = noName;
            }))
          ]
          ++ noName;
        }).config.id_hash;
      expectedError = {
        type = "ThrownError";
        msg = "^gen-schema: mkIdentityModule: kind 'host' identifies instances by 'name', which this instance does not declare \\(identity keys: load, name\\); 'name' is reserved and is declared by mkInstanceType$";
      };
    };
  };
}
