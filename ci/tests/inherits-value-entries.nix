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
    (genMerge.evalModuleTree { } ([ { options.schema = mkSchemaOption { }; } ] ++ modules))
    .config.schema;
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
    evalSchema { } [
      { config.schema.base.options.b = strOpt; }
      { config.schema.sub = entry spelling foreign; }
    ];
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
    # A SELF-NAMED SUBKIND: the declaring kind keeps the foreign value's name (`base` inherits the
    # foreign `base`). The tree's entry at that name is the declaring kind itself, whose mark is in
    # flight, so the discriminator decides it by witness before any mark: a foreign VALUE entry.
    test-self-named-subkind-composes-a-foreign-value = {
      expr =
        let
          rec' = t: {
            inherits = map (render t) t.base.inherits;
            edges = map (e: render t e.to) (builtins.filter (e: e.type == "inherits") t._edges);
            options = builtins.attrNames t.base.options;
            isAForeign = isA foreign t.base;
          };
          decl = spelling: { config.schema.base = entry spelling foreign; };
        in
        {
          inherits = rec' (tree [ (decl "inherits") ]);
          alias = rec' (tree [ (decl "alias") ]);
          evalSchema = rec' (evalSchema { } [ (decl "inherits") ]);
        };
      expected =
        let
          r = {
            inherits = [ "value:foreign" ];
            edges = [ "value:foreign" ];
            options = [
              "b"
              "extra"
            ];
            isAForeign = true;
          };
        in
        {
          inherits = r;
          alias = r;
          evalSchema = r;
        };
    };
    # The same, on the `mkType` arm, with a caller `mkType` whose result's SHAPE reads the defs (as
    # gen-aspects' `optionalAttrs (defsModules != [ ])` does): the declaring kind has no value while
    # its `inherits` is classified, so its own name is decided by the name, never by forcing it.
    test-self-named-subkind-on-the-mkType-arm = {
      expr =
        let
          mkType =
            {
              defs ? [ ],
              kind,
              ...
            }:
            {
              __functor = _: _: {
                imports = map (d: d.value) (builtins.filter (d: builtins.isAttrs d.value) defs);
              };
              inherit kind;
            }
            // (if builtins.length defs > 0 then { hasDefs = true; } else { });
          k =
            (genMerge.evalModuleTree { } [
              { options.schema = mkSchemaOption { inherit mkType; }; }
              { config.schema.base = entry "inherits" foreign; }
            ]).config.schema.base;
        in
        {
          inherits = map (e: mark e == mark foreign) k.inherits;
          isAForeign = isA foreign k;
          hasDefs = k.hasDefs;
        };
      expected = {
        inherits = [ true ];
        isAForeign = true;
        hasDefs = true;
      };
    };
    # The general case: the value's name is held in-tree by a kind that INHERITS the declaring kind
    # (local `base` inherits `sub` by name; `sub` inherits the foreign `base`). No cycle.
    test-name-held-by-a-descendant-composes-a-foreign-value = {
      expr =
        let
          t =
            spelling:
            tree [
              {
                config.schema.base = {
                  inherits = [ "sub" ];
                  options.lb = intOpt;
                };
              }
              { config.schema.sub = entry spelling foreign; }
            ];
          rec' = t: {
            inherits = map (render t) t.sub.inherits;
            sub = builtins.attrNames t.sub.options;
            base = builtins.attrNames t.base.options;
            isAForeign = isA foreign t.sub;
          };
        in
        {
          inherits = rec' (t "inherits");
          alias = rec' (t "alias");
        };
      expected =
        let
          r = {
            inherits = [ "value:foreign" ];
            sub = [
              "b"
              "extra"
            ];
            base = [
              "b"
              "extra"
              "lb"
            ];
            isAForeign = true;
          };
        in
        {
          inherits = r;
          alias = r;
        };
    };
    # The same topology on the `mkType` arm, with a caller `mkType` whose result shape reads the defs
    # (den-hoag-24zdh): the kind has a WHNF before any parent is classified, so the reach walk reads
    # the declaring kind's witness and the foreign value composes as on the default arm.
    test-name-held-by-a-descendant-on-the-mkType-arm-composes = {
      expr =
        let
          mkType =
            {
              defs ? [ ],
              kind,
              ...
            }:
            {
              __functor = _: _: {
                imports = map (d: d.value) (builtins.filter (d: builtins.isAttrs d.value) defs);
              };
              inherit kind;
            }
            // (if builtins.length defs > 0 then { hasDefs = true; } else { });
          t =
            (genMerge.evalModuleTree { } [
              { options.schema = mkSchemaOption { inherit mkType; }; }
              {
                config.schema.base = {
                  inherits = [ "sub" ];
                  options.lb = intOpt;
                };
              }
              { config.schema.sub = entry "inherits" foreign; }
            ]).config.schema;
        in
        {
          sub = builtins.attrNames t.sub.options;
          base = builtins.attrNames t.base.options;
        };
      expected = {
        sub = [
          "b"
          "extra"
        ];
        base = [
          "b"
          "extra"
          "lb"
        ];
      };
    };
    # The self-named topology at depth 3 (each tree's `base` inherits the previous tree's), its layers
    # from one generator. Each layer adds its own option, so no two layers share a witness; the
    # equal-witness chain is refused, enumerated in `ci/tests-error.nix`.
    test-self-named-chain-of-three-composes = {
      expr =
        let
          layer = parent: o: {
            config.schema.base = {
              inherits = [ parent ];
              options.${o} = intOpt;
            };
          };
          t1 = tree [ (layer foreign "x") ];
          t2 = tree [ (layer t1.base "y") ];
        in
        {
          options = builtins.attrNames t2.base.options;
          isAForeign = isA foreign t2.base;
        };
      expected = {
        options = [
          "b"
          "x"
          "y"
        ];
        isAForeign = true;
      };
    };
    # OQ8: a value needs no tree to resolve, so an entry type built outside a kind tree composes it
    test-treeless-entry-composes-a-value-entry = {
      expr =
        let
          sub =
            (genMerge.evalModuleTree { } [
              {
                options.kinds = genMerge.mkOption {
                  type = T.lazyAttrsOf (mkSchemaEntryType { });
                };
                config.kinds.sub = entry "inherits" foreign;
              }
            ]).config.kinds.sub;
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
