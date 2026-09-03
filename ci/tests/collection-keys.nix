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
}
