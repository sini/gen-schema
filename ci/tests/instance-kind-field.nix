# `_kind` — the instance carries its own kind.
#
# A node in the schema graph is identified by `(kind, name)`. An instance carrying only `name` is half a
# node, so every consumer holding a bare instance has to recover the kind from outside it — from the
# registry key (consumer-chosen, so a guess) or by recomputing `id_hash` against each candidate kind. The
# constructor already has the kind (`mkInstanceType` takes the kind VALUE), so the binding exists at
# construction and only needs to be kept.
#
# The property that makes keeping it safe: `_kind` is INVISIBLE TO IDENTITY. `mkIdentityModule` reflects
# the kind's options (skipping `_`-prefixed names and non-primitive types) and `identityHashFor` reflects
# the instance's values (skipping `_`-prefixed keys), so a `_`-prefixed `raw` option is excluded by both.
#
# The identity pin is a HASH LITERAL, deliberately. A pin that compared "instance with the field" against
# "instance with the field" could not fail: typing `_kind` as `str` would move both sides together and
# read green. The literal moves alone.
{
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema)
    mkSchemaOption
    mkInstanceRegistry
    mkInstanceType
    mkIdentityModule
    ;

  # Through the registry — i.e. through the whole apply pipeline (validate → refine → derive), not just
  # the bare type: a field the pipeline dropped would be present on the type and absent where consumers
  # actually read.
  eval = genMerge.evalModuleTree {
    modules = [
      {
        options.schema = mkSchemaOption { };
        options.zones = mkInstanceRegistry eval.config.schema.zone { };
        config.schema.zone.options.domain = genMerge.mkOption { type = genMerge.types.str; };
        config.zones.z1.domain = "example.test";
      }
    ];
  };

  # A registry whose namespace does NOT match the kind name — the shape the field exists for. `rackFarm`
  # holds kind `rack`; nothing about the key says so.
  renamed = genMerge.evalModuleTree {
    modules = [
      {
        options.schema = mkSchemaOption { };
        options.rackFarm = mkInstanceRegistry renamed.config.schema.rack { };
        config.schema.rack.options.slot = genMerge.mkOption { type = genMerge.types.int; };
        config.rackFarm.r1.slot = 3;
      }
    ];
  };

  # A hand-rolled registry — `attrsOf (mkInstanceType …)` without `mkInstanceRegistry`. The field is
  # declared on the TYPE, so this construction carries it too.
  handRolled = genMerge.evalModuleTree {
    modules = [
      {
        options.schema = mkSchemaOption { };
        options.zones = genMerge.mkOption {
          type = genMerge.types.attrsOf (mkInstanceType handRolled.config.schema.zone { });
          default = { };
        };
        config.schema.zone.options.domain = genMerge.mkOption { type = genMerge.types.str; };
        config.zones.z1.domain = "example.test";
      }
    ];
  };

  strictEval = genMerge.evalModuleTree {
    modules = [
      {
        options.schema = mkSchemaOption { };
        options.zones = mkInstanceRegistry strictEval.config.schema.zone { };
        config.schema.zone.strict = true;
        config.schema.zone.options.domain = genMerge.mkOption { type = genMerge.types.str; };
        config.zones.z1.domain = "example.test";
      }
    ];
  };

  # A kind that PINS its identity keys, so the key set has contents to assert against.
  explicitKeys = genMerge.evalModuleTree {
    modules = [
      {
        options.schema = mkSchemaOption { };
        options.zones = mkInstanceRegistry explicitKeys.config.schema.zone { };
        config.schema.zone.options.domain = genMerge.mkOption { type = genMerge.types.str; };
        config.zones.z1 = {
          domain = "example.test";
          _identity.keys = [ "domain" ];
        };
      }
    ];
  };

  # The identity CONTROL: the same kind and the same identity-bearing values, hashed with no `_kind`
  # option declared at all. Equality with the registry instance is what "invisible to identity" means.
  control = genMerge.evalModuleTree {
    modules = [
      (mkIdentityModule "zone")
      {
        options.name = genMerge.mkOption { type = genMerge.types.str; };
        options.domain = genMerge.mkOption { type = genMerge.types.str; };
      }
      {
        config.name = "z1";
        config.domain = "example.test";
      }
    ];
  };
in
{
  flake.tests.instance-kind-field.test-instance-carries-its-kind = {
    expr = eval.config.zones.z1._kind;
    expected = "zone";
  };
  # The point of the field: the answer comes from the record, not from the namespace.
  flake.tests.instance-kind-field.test-kind-is-independent-of-the-registry-key = {
    expr = renamed.config.rackFarm.r1._kind;
    expected = "rack";
  };
  flake.tests.instance-kind-field.test-hand-rolled-instance-type-carries-it = {
    expr = handRolled.config.zones.z1._kind;
    expected = "zone";
  };
  flake.tests.instance-kind-field.test-strict-kind-admits-it = {
    expr = strictEval.config.zones.z1._kind;
    expected = "zone";
  };
  # Identity: pinned to a literal, so a field that became identity-visible moves this alone.
  flake.tests.instance-kind-field.test-id-hash-literal-unmoved = {
    expr = eval.config.zones.z1.id_hash;
    expected = "f63b75fd9b145f618dc40dc00395840e7a5c786860739cb0e61f3816adbe658d";
  };
  # …and the same hash a `_kind`-less eval of the same kind and values produces.
  flake.tests.instance-kind-field.test-id-hash-equals-field-less-control = {
    expr = eval.config.zones.z1.id_hash == control.config.id_hash;
    expected = true;
  };
  # The value-reflecting recompute (kind-external consumers) must agree too — it skips `_`-prefixed keys
  # on the INSTANCE, a different code path from the option reflection above.
  flake.tests.instance-kind-field.test-value-reflection-still-matches = {
    expr = genSchema.identityHashFor "zone" eval.config.zones.z1 == eval.config.zones.z1.id_hash;
    expected = true;
  };
  # The identity KEY set is untouched. Pinned on a kind that PINS its keys explicitly — under reflection
  # `_identity.keys` is `[ ]` on both sides, so comparing the two there would be a check that cannot fail.
  flake.tests.instance-kind-field.test-explicit-identity-keys-exclude-it = {
    expr = explicitKeys.config.zones.z1._identity.keys;
    expected = [ "domain" ];
  };
}
