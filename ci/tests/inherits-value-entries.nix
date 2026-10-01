# `inherits` ACCEPTS A KIND VALUE (den-hoag-l0y U2) — the cells that must stay GREEN.
#
# A same-tree value is the name (F4). A foreign value is a VALUE entry, distinct from every name in
# `inherits` and in the `_edges` row's `to`, and composes as itself (N2). The deprecated spelling
# `imports = [ <value> ]` reads through the same discriminator (K1), so every N2 cell runs on both
# spellings and the two records must be identical. The by-name refusals (the open twin, a value
# that is not a kind, the value-spelling cycles) live in `ci/tests-error.nix`.
{
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema)
    evalSchema
    mkSchemaOption
    mkSchemaEntryType
    kindEq
    ;
  T = genMerge.types;
  intOpt = genMerge.mkOption { type = T.int; };
  strOpt = genMerge.mkOption { type = T.str; };
  tree =
    modules:
    (genMerge.evalModuleTree {
      modules = [ { options.schema = mkSchemaOption { }; } ] ++ modules;
    }).config.schema;
  mark = k: k.__mint.minted;
  isA =
    k: v:
    if mark v == mark k then
      kindEq v k
    else
      v.__kindAncestors ? ${mark k} && kindEq v.__kindAncestors.${mark k} k;

  # the foreign kind: `base` with `b : int`, from a tree of its own
  foreign = (tree [ { config.schema.base.options.b = intOpt; } ]).base;
  entry =
    spelling: v:
    (if spelling == "alias" then { imports = [ v ]; } else { inherits = [ v ]; })
    // {
      options.extra = intOpt;
    };
  # a consumer tree holding its OWN `base` (typed `own`), whose `sub` takes `parent` by value
  treeOf =
    spelling: own: parent:
    tree [
      { config.schema.base.options.b = own; }
      (
        { config, ... }:
        {
          config.schema.sub = entry spelling (if parent == "same" then config.schema.base else parent);
        }
      )
    ];
  render =
    t: e:
    if builtins.isString e then
      e
    else if mark e == mark foreign then
      "value:foreign"
    else
      "value:other";
  recordOf = t: {
    inherits = map (render t) t.sub.inherits;
    edges = map (e: render t e.to) (
      builtins.filter (e: e.type == "inherits" && e.from == "sub") t._edges
    );
    bType = t.sub.options.b.type.name;
    isAForeign = isA foreign t.sub;
    isALocal = isA t.base t.sub;
  };
  n2For = spelling: {
    # the consumer's `base` is `str`: the foreign `base` is another kind
    distinct = recordOf (treeOf spelling strOpt foreign);
    # the tree's own kind, by value: the name (F4)
    same = recordOf (treeOf spelling intOpt "same");
    # the consumer's `base` is an independent construction of the same declaration: one kind by
    # identity law (ADR-0034), so the name
    typeTwin = recordOf (treeOf spelling intOpt foreign);
    distinctEntryIsTheValue = kindEq (builtins.head
      (treeOf spelling strOpt foreign).sub.inherits
    ) foreign;
  };
  n2 = {
    distinct = {
      inherits = [ "value:foreign" ];
      edges = [ "value:foreign" ];
      bType = "int";
      isAForeign = true;
      isALocal = false;
    };
    same = {
      inherits = [ "base" ];
      edges = [ "base" ];
      bType = "int";
      isAForeign = true;
      isALocal = true;
    };
    typeTwin = {
      inherits = [ "base" ];
      edges = [ "base" ];
      bType = "int";
      isAForeign = true;
      isALocal = true;
    };
    distinctEntryIsTheValue = true;
  };

  # the `evalSchema` arm (OQ7): a value entry stages nothing, and composes as itself
  esOf =
    spelling:
    evalSchema {
      modules = [
        { config.schema.base.options.b = strOpt; }
        { config.schema.sub = entry spelling foreign; }
      ];
    };
  esRecordOf = t: {
    inherits = map (render t) t.sub.inherits;
    bType = t.sub.options.b.type.name;
    isAForeign = isA foreign t.sub;
    isALocal = isA t.base t.sub;
  };
in
{
  flake.tests.inherits-value-entries = {
    test-inherits-value-entry-is-distinct-from-a-name = {
      expr = n2For "inherits";
      expected = n2;
    };
    # K1: the deprecated spelling records exactly what `inherits = [ <value> ]` records
    test-alias-value-entry-is-distinct-from-a-name = {
      expr = n2For "alias";
      expected = n2;
    };
    test-evalSchema-arm-accepts-a-value-entry = {
      expr = {
        inherits = esRecordOf (esOf "inherits");
        alias = esRecordOf (esOf "alias");
      };
      expected =
        let
          r = {
            inherits = [ "value:foreign" ];
            bType = "int";
            isAForeign = true;
            isALocal = false;
          };
        in
        {
          inherits = r;
          alias = r;
        };
    };
    # OQ8: a value needs no tree to resolve, so an entry type built outside a kind tree composes it
    test-treeless-entry-composes-a-value-entry = {
      expr =
        let
          sub =
            (genMerge.evalModuleTree {
              modules = [
                {
                  options.kinds = genMerge.mkOption {
                    type = T.lazyAttrsOf (mkSchemaEntryType { });
                  };
                  config.kinds.sub = entry "inherits" foreign;
                }
              ];
            }).config.kinds.sub;
        in
        {
          options = builtins.attrNames sub.options;
          inherits = map (e: mark e == mark foreign) sub.inherits;
          isAForeign = isA foreign sub;
        };
      expected = {
        options = [
          "b"
          "extra"
        ];
        inherits = [ true ];
        isAForeign = true;
      };
    };
  };
}
