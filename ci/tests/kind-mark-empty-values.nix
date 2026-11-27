# `{ }` AGAINST `[ ]` IN THE KIND MARK (ADR-0034, inheriting ADR-0016 ruling 4: identity follows Nix `==` in both
# directions). Two kinds that differ only in holding `{ }` where the other holds `[ ]` are two values, so they read two
# marks, `kindEq` decides them `false`, and every reader of the mark keeps them apart: `inherits` records the foreign
# value as a value, and nixpkgs' `evalModules`, which dedups kinds by their foreign key, imports both and refuses the
# option they both declare. Each row builds kind `k` twice, each in its own schema evaluation, at one definition
# literal, so the two sit at one declaration node; it reads `{ m; eq; }` (marks equal, `kindEq`). Every place the
# mark reads a value is a row: a kept collection's value, a typed collection's own empty value, and keySemantics.
# Twins (the equality arm) and a discriminating control (the inequality arm) are read beside them.
{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  T = genMerge.types;
  try =
    v:
    let
      r = builtins.tryEval (builtins.deepSeq v v);
    in
    if r.success then r.value else "REFUSED";
  kOf =
    args: defs:
    (genMerge.evalModuleTree { } (
      [
        { options.schema = genSchema.mkSchemaOption args; }
        { config.schema.k = { }; }
      ]
      ++ map (d: { config.schema.k = d; }) defs
    )).config.schema.k;
  read = a: b: {
    m = try (a.__mint.minted == b.__mint.minted);
    eq = try (genSchema.kindEq a b);
  };
  # one definition literal for both sides
  one = v: [ { c = v; } ];
  pair =
    argsA: argsB: a: b:
    read (kOf argsA a) (kOf argsB b);
  coll = t: { collections.c = t; };
  any = coll { type = T.anything; };
  raw = coll { type = T.raw; };
  vs =
    args: a: b:
    pair args args (one a) (one b);
  # (ii): a schema holding kind `p` (`c = x`), optionally beside a kind `q` inheriting a foreign value
  tree =
    x: extra:
    (genMerge.evalModuleTree { } [
      { options.schema = genSchema.mkSchemaOption any; }
      { config.schema.p.c = x; }
      { config.schema = extra; }
    ]).config.schema;
  pOf = x: (tree x { }).p;
  inheritsRead =
    x: y:
    try (
      map (v: if builtins.isString v then "name:${v}" else "value:${v.kind}")
        (tree x { q.inherits = [ (pOf y) ]; }).q.inherits
    );
  # (iii) the same `p`, declaring one option `o`
  pO =
    x:
    (genMerge.evalModuleTree { } [
      { options.schema = genSchema.mkSchemaOption any; }
      {
        config.schema.p = {
          c = x;
          options.o = genMerge.mkOption {
            type = T.str;
            default = "d";
          };
        };
      }
    ]).config.schema.p;
  nixpkgsBoth =
    x: y:
    let
      r = builtins.tryEval (
        builtins.deepSeq
          (lib.evalModules {
            modules = [
              (pO x)
              (pO y)
            ];
          }).config.o
          "imports-cleanly"
      );
    in
    if r.success then r.value else "REFUSED";
in
{
  flake.tests.kind-mark-empty-values = {
    test-the-mark-tells-an-empty-record-from-an-empty-list = {
      expr = {
        kept = vs any { } [ ];
        keptRaw = vs raw { } [ ];
        typedEmptyValues = pair (coll { type = T.attrsOf T.str; }) (coll {
          type = T.listOf T.str;
        }) [ ] [ ];
        typedDefined = pair (coll { type = T.attrsOf T.str; }) (coll { type = T.listOf T.str; }) (one { }) (
          one [ ]
        );
        keySemantics = pair (any // { keySemantics = { }; }) (any // { keySemantics = [ ]; }) [ ] [ ];
      };
      expected = lib.genAttrs [ "kept" "keptRaw" "typedEmptyValues" "typedDefined" "keySemantics" ] (_: {
        m = false;
        eq = false;
      });
    };
    # the equality arm and the inequality arm, both firing in the same file
    test-empty-twins-join-and-a-non-empty-control-separates = {
      expr = {
        twinEmptySet = vs any { } { };
        twinEmptyList = vs any [ ] [ ];
        controlList = vs any [ ] [ "a" ];
        controlSet = vs any { } { a = "x"; };
      };
      expected = {
        twinEmptySet = {
          m = true;
          eq = true;
        };
        twinEmptyList = {
          m = true;
          eq = true;
        };
        controlList = {
          m = false;
          eq = false;
        };
        controlSet = {
          m = false;
          eq = false;
        };
      };
    };
    # a foreign kind holding `[ ]` beside the tree's own `p` holding `{ }` is a value, never the tree's `p`
    test-inherits-keeps-a-foreign-empty-value-apart-from-the-own-kind = {
      expr = {
        listVsSet = inheritsRead [ ] { };
        setVsList = inheritsRead { } [ ];
        twin = inheritsRead { } { };
        control = inheritsRead [ ] [ "a" ];
      };
      expected = {
        listVsSet = [ "value:p" ];
        setVsList = [ "value:p" ];
        twin = [ "name:p" ];
        control = [ "value:p" ];
      };
    };
    # nixpkgs dedups kinds by their foreign key: two that differ refuse the option both declare
    test-nixpkgs-imports-both-empty-kinds-and-refuses-their-shared-option = {
      expr = {
        listVsSet = nixpkgsBoth [ ] { };
        setVsList = nixpkgsBoth { } [ ];
        twin = nixpkgsBoth { } { };
        control = nixpkgsBoth [ ] [ "a" ];
      };
      expected = {
        listVsSet = "REFUSED";
        setVsList = "REFUSED";
        twin = "imports-cleanly";
        control = "REFUSED";
      };
    };
  };
}
