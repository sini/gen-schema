# den-hoag-4kh.53.55: the collection key set is a projection gen-schema derives, consumes
# and never named. `_collectionKeys` publishes it at the post-evaluation position, from the
# same `mkAllCollections` derivation the entry type extracts with — so a consumer standing on
# `config.schema` reads the set instead of re-declaring it (den-hoag's `schemaCollectionKeys`
# is a nine-element hand literal standing in for a derived four).
{
  lib,
  genSchema,
  genMerge,
  prelude,
  ...
}:
let
  inherit (genSchema) mkSchemaOption;
  inherit (genMerge) mkOption types evalModuleTree;

  str = mkOption { type = types.str; };

  # One declared collection, one kind that fills it.
  plain = evalModuleTree {
    modules = [
      {
        options.schema = mkSchemaOption {
          collections.includes = {
            default = [ ];
          };
        };
        config.schema.host = {
          options.addr = str;
          includes = [ "policy-a" ];
        };
      }
    ];
  };
  plainKind = plain.config.schema.host;

  # No caller collections — the built-in base alone.
  noCols = evalModuleTree {
    modules = [
      {
        options.schema = mkSchemaOption { };
        config.schema.host.options.addr = str;
      }
    ];
  };

  # Two caller collections — the input the base-only arm never supplies.
  twoCols = evalModuleTree {
    modules = [
      {
        options.schema = mkSchemaOption {
          collections.includes = {
            default = [ ];
          };
          collections.excludes = {
            default = [ ];
          };
        };
        config.schema.host.options.addr = str;
      }
    ];
  };

  # Two ordinary kinds — the seventh internal option must not disturb _kindNames.
  ordinary = evalModuleTree {
    modules = [
      {
        options.schema = mkSchemaOption { };
        config.schema.host.options.addr = str;
        config.schema.user.options.userName = str;
      }
    ];
  };

  # A reserved COLLECTION key with ZERO kinds declared. The refusal lives inside the hoisted
  # body, so the published read reaches it — a respelling outside the guard would not.
  readKeys =
    collections:
    let
      e = evalModuleTree {
        modules = [ { options.schema = mkSchemaOption { inherit collections; }; } ];
      };
    in
    builtins.tryEval (builtins.deepSeq e.config.schema._collectionKeys e.config.schema._collectionKeys);
  reservedColAttempt = readKeys {
    __functor = {
      default = { };
    };
  };
  fineColAttempt = readKeys {
    fine = {
      default = { };
    };
  };

  # den-hoag-25mae. A user kind NAMED AFTER a declared internal introspection option. Every
  # existing cell for this behaviour observes the internal names as OPTION DECLARATIONS, on a
  # schema where no user kind carries one -- this is the collision input, and nothing exercised
  # it. `host` is load-bearing: without it `_kindNames` reads `[ ]`, which is also what a fixture
  # declaring no kinds at all returns -- a value that cannot fail.
  collidePlus = evalModuleTree {
    modules = [
      {
        options.schema = mkSchemaOption { };
        config.schema._collectionKeys = {
          options.x = str;
        };
        config.schema.host = {
          options.addr = str;
        };
      }
    ];
  };
in
{
  # O1 — the surface exists where a consumer stands, holding config.schema and nothing else.
  flake.tests.collection-keys.test-published-at-schema-level = {
    expr = plain.config.schema._collectionKeys;
    expected = [
      "includes"
      "methods"
      "parent"
      "validators"
    ];
  };

  # O2 — it TRACKS the caller's argument. A build hardcoding O1's four-element answer passes
  # O1 and reds both arms here.
  flake.tests.collection-keys.test-base-only-without-collections = {
    expr = noCols.config.schema._collectionKeys;
    expected = [
      "methods"
      "parent"
      "validators"
    ];
  };
  flake.tests.collection-keys.test-tracks-declared-collections = {
    expr = twoCols.config.schema._collectionKeys;
    expected = [
      "excludes"
      "includes"
      "methods"
      "parent"
      "validators"
    ];
  };

  # O3 — `internal = true` on the seventh option is what keeps it out of _kindNames. Drop that
  # flag and `_collectionKeys` reads as a `_`-prefixed KIND name, which _kindNames refuses
  # outright — so this cell throws rather than merely widening. The refusal itself is still
  # exercised by introspect-kind-names.test-underscore-kind-name-throws (`_hidden`).
  flake.tests.collection-keys.test-control-kindNames-excludes-seventh-option = {
    expr = ordinary.config.schema._kindNames;
    expected = [
      "host"
      "user"
    ];
  };

  # O4 — one read, no filter: positive selection over the published set, and the values land.
  flake.tests.collection-keys.test-idiom-reads-every-collection = {
    expr = prelude.genAttrs plain.config.schema._collectionKeys (k: plainKind.${k});
    expected = {
      includes = [ "policy-a" ];
      methods = { };
      parent = null;
      validators = [ ];
    };
  };
  # Controls: the published set is exactly the STRIPPED set — a collection key is gone from
  # the kind's options, an ordinary option is not.
  flake.tests.collection-keys.test-control-collection-key-stripped-from-options = {
    expr = plainKind.options ? includes;
    expected = false;
  };
  flake.tests.collection-keys.test-control-ordinary-option-survives = {
    expr = plainKind.options ? addr;
    expected = true;
  };

  # O5 — the reserved-key refusals stayed INSIDE the shared derivation. This is the cell that
  # separates the hoist from a second spelling inside mkSchemaOption, which would hand back
  # `[ "__functor" "methods" "parent" "validators" ]` silently.
  flake.tests.collection-keys.test-reserved-collection-refused-on-published-read = {
    expr = reservedColAttempt.success;
    expected = false;
  };
  flake.tests.collection-keys.test-control-ordinary-collection-read-succeeds = {
    expr = fineColAttempt.value;
    expected = [
      "fine"
      "methods"
      "parent"
      "validators"
    ];
  };

  # O6 -- the collision input, the one arm the filtered/refused pair is missing. An ARBITRARY `_`
  # kind name is refused by name (introspect-names.test-underscore-kind-name-throws); a name that
  # COLLIDES with a declared internal option is not, because `reservedKindNames` tests
  # `!(isInternalField n)` first -- so `_kindNames` answers and drops it, and the collision
  # surfaces only when `_collectionKeys` is forced.
  flake.tests.collection-keys.test-collectionkeys-kind-filtered-not-refused = {
    expr = collidePlus.config.schema._kindNames;
    expected = [ "host" ];
  };
  # The force-time refusal itself. COMPANION, not a discriminator: measured, no mutation of
  # entry-type.nix reachable within `tryEval` moves this value -- dropping `readOnly` or the
  # `config._collectionKeys` assignment aborts uncatchably and takes any control with it, and
  # `type = raw` still refuses. It pins documented behaviour and is marked so no reader mistakes
  # it for a guard; the discriminating cell is the one above, and the standing control that
  # exercises `_collectionKeys` at a non-colliding input is `test-published-at-schema-level`.
  flake.tests.collection-keys.test-collectionkeys-collision-refused-at-force = {
    expr = (builtins.tryEval (builtins.deepSeq collidePlus.config.schema._collectionKeys true)).success;
    expected = false;
  };
}
