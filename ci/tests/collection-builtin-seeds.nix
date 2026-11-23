{ genMerge, genSchema, ... }:
let
  # The library constants the built-in collections are seeded with. The library writes them twice: as
  # `mkAllCollections`' defaults, which a kind holds where it defines none, and as `keySchema.builtinSeeds`, by which
  # the kind key names a built-in held at its constant (`constNamed`). Drift between the two leaves a kind at the
  # served default unnamed and at its seed, and its key aborts at `keySchema.seedTags`, which holds no built-in.
  constants = {
    methods = { };
    validators = [ ];
    parent = null;
    inherits = [ ];
  };
  kindOf =
    decl:
    (genMerge.evalModuleTree { } [
      { options.schema = genSchema.mkSchemaOption { }; }
      { config.schema.k = decl; }
    ]).config.schema.k;
  decl = {
    options.name = genMerge.mkOption { type = genMerge.types.str; };
  };
  served = kindOf decl;
  stated = kindOf (decl // constants);
  # the key's separation part, after `gen-schema-kind:<kind>#<witness>#`: the witness carries the declaration's position
  key = k: builtins.match "[^#]*#[^#]*#(.*)" (k.__functor k { }).key;
in
{
  # `mkAllCollections`' side: a kind defining no built-in holds the constants.
  flake.tests.collection-builtin-seeds.test-the-served-built-in-defaults-are-the-constants = {
    expr = builtins.intersectAttrs constants served;
    expected = constants;
  };
  # `builtinSeeds`' side: the kind at the served defaults keys as the kind stating the constants. A drift on either
  # side aborts this cell, uncatchably, at `keySchema.seedTags`.
  flake.tests.collection-builtin-seeds.test-a-kind-at-the-served-defaults-keys-as-one-stating-the-constants = {
    expr = key served != null && key served == key stated;
    expected = true;
  };
}
