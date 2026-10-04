# THE CONTENT WITNESS ACROSS TREES (den-hoag-4i0o5) — the cells that must stay GREEN.
#
# A witness is read before composition: the kind's name, each def's file and position, its parents'
# names and its option names. One declaration applied in two trees (a layer helper) therefore gives
# two kinds one witness, and the cycle walk cannot tell a chain through them from a cycle. The
# refusal says so (`ci/tests-error.nix`, `witness-collision-refusals`); these cells pin the remedy it
# names, provenance: the same chain with each application given its own module `_file` is served
# (a module VALUE or a module imported by path, which is named by the `_file` its own content sets,
# else its path). The tagged cycle's refusal is pinned by message there.
{
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) mkSchemaOption;
  intOpt = genMerge.mkOption { type = genMerge.types.int; };
  tree =
    modules:
    (genMerge.evalModuleTree { } ([ { options.schema = mkSchemaOption { }; } ] ++ modules))
    .config.schema;
  # ONE source position for every application.
  layer = name: parent: o: {
    config.schema.${name} = {
      inherits = [ parent ];
      options.${o} = intOpt;
    };
  };
  tagged =
    tag: name: parent: o:
    layer name parent o // { _file = "layer:${tag}"; };

  # base <- mid <- base <- mid: the two `base`s are one declaration applied in two trees, and the
  # chain is acyclic.
  m0 = tree [ { config.schema.mid.options.m = intOpt; } ];
  chain = l: rec {
    u1 = tree [ (l "u1" "base" m0.mid "x") ];
    m1 = tree [ (l "m1" "mid" u1.base "m2") ];
    u2 = tree [ (l "u2" "base" m1.mid "x") ];
  };
  untagged = chain (_: layer);
  byFile = chain tagged;

  # self-named: t0 <- t1 <- t2, each `base` inheriting the previous tree's `base`
  t0 = tree [ { config.schema.base.options.b = intOpt; } ];
  t1 = tree [ (tagged "1" "base" t0.base "x") ];
  t2 = tree [ (tagged "2" "base" t1.base "x") ];

  # options through the entry's `imports`, tagged: served, so the untagged collision is acyclic
  ilayer = tag: parent: extra: {
    _file = "ilayer:${tag}";
    config.schema.base = {
      inherits = [ parent ];
      imports = [ extra ];
    };
  };
  i1 = tree [ (ilayer "1" t0.base { options.y1 = intOpt; }) ];
  i2 = tree [ (ilayer "2" i1.base { options.y2 = intOpt; }) ];

  # one layer FILE: imported as a value and tagged, or a second file at a distinct path
  asValue =
    tag: parent:
    import ../test-fixtures/shared-layer.nix { inherit parent intOpt; } // { _file = "value:${tag}"; };
  sv1 = tree [ (asValue "1" t0.base) ];
  sv2 = tree [ (asValue "2" sv1.base) ];
  byPath =
    file: parent:
    (genMerge.evalModuleTree { specialArgs = { inherit parent intOpt; }; } [
      { options.schema = mkSchemaOption { }; }
      file
    ]).config.schema;
  # one layer FILE that sets its own `_file` per application, imported by path (tag via specialArgs)
  byPathTagged =
    file: tag: parent:
    (genMerge.evalModuleTree { specialArgs = { inherit parent intOpt tag; }; } [
      { options.schema = mkSchemaOption { }; }
      file
    ]).config.schema;
  pt1 = byPathTagged ../test-fixtures/shared-layer-tagged.nix "1" t0.base;
  pt2 = byPathTagged ../test-fixtures/shared-layer-tagged.nix "2" pt1.base;
  # the same applications from two DISTINCT path modules that set ONE `_file`
  ga = byPathTagged ../test-fixtures/shared-layer-generated-a.nix "" t0.base;
  gb = byPathTagged ../test-fixtures/shared-layer-generated-b.nix "" t0.base;
  pt1b = byPathTagged ../test-fixtures/shared-layer-tagged.nix "1" t0.base;
  sh1 = byPath ../test-fixtures/shared-layer.nix t0.base;
  sc2 = byPath ../test-fixtures/shared-layer-copy.nix sh1.base;
in
{
  flake.tests.kind-witness-collision = {
    test-one-declaration-in-two-trees-shares-a-witness = {
      expr = untagged.u1.base.__kindWitness == untagged.u2.base.__kindWitness;
      expected = true;
    };
    test-a-module-file-per-application-separates-the-witness = {
      expr = byFile.u1.base.__kindWitness == byFile.u2.base.__kindWitness;
      expected = false;
    };
    test-a-tagged-chain-is-served = {
      expr = builtins.attrNames byFile.u2.base.options;
      expected = [
        "m"
        "m2"
        "x"
      ];
    };
    test-a-tagged-self-named-chain-is-served = {
      expr = builtins.attrNames t2.base.options;
      expected = [
        "b"
        "x"
      ];
    };
    test-tagged-options-through-imports-are-served = {
      expr = builtins.attrNames i2.base.options;
      expected = [
        "b"
        "y1"
        "y2"
      ];
    };
    test-a-path-module-imported-as-a-tagged-value-is-served = {
      expr = builtins.attrNames sv2.base.options;
      expected = [
        "b"
        "x"
      ];
    };
    # A path module is named by the `_file` its own content sets (den-hoag-6fqay): two applications
    # tagged differently separate the witness, and the chain through them is served. Was a refusal.
    test-a-path-module-setting-its-own-file-separates-the-witness = {
      expr = pt1.base.__kindWitness == pt2.base.__kindWitness;
      expected = false;
    };
    test-a-path-module-setting-its-own-file-is-served = {
      expr = builtins.attrNames pt2.base.options;
      expected = [
        "b"
        "x"
      ];
    };
    # The converse direction: two DISTINCT path modules with one `_file` and a generated (position-less)
    # value, the same parents and the same option names, are named alike, so their witnesses agree (they
    # differed by path before). A literal value still differs by its source position.
    test-two-path-modules-setting-one-file-share-a-witness = {
      expr = {
        distinctPaths = ga.base.__kindWitness == gb.base.__kindWitness;
        samePathSameApplication = pt1.base.__kindWitness == pt1b.base.__kindWitness;
      };
      expected = {
        distinctPaths = true;
        samePathSameApplication = true;
      };
    };
    test-a-path-module-at-a-distinct-path-is-served = {
      expr = builtins.attrNames sc2.base.options;
      expected = [
        "b"
        "x"
      ];
    };
  };
}
