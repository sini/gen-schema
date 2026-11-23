{ genSchema, ... }:
let
  inherit (genSchema._internal) builtinSeeds mkAllCollections;
in
{
  # The kind key names a built-in held at `builtinSeeds`' constant (`constNamed`) and reads a declared seed by
  # `keySchema.seedTags`, which holds no built-in. The two literals must agree: a drifted `mkAllCollections`
  # default leaves a kind at that default unnamed and at its seed, and its key aborts at `seedTags`, uncatchably.
  flake.tests.collection-builtin-seeds.test-builtin-seeds-are-the-served-defaults = {
    expr = builtins.mapAttrs (_: c: c.default) (mkAllCollections null null { });
    expected = builtinSeeds;
  };
}
