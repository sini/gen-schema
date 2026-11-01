# THE `mkType` ARM IS A NODE OF GEN'S GRAPH AS THE DEFAULT ARM IS (den-hoag-a7c9r V1-a, OQ-8): both arms
# publish one node record (`kindNodeRecord`), so an ancestor reached through two children is one module
# and its `default` is declared once. Each row reads `[ d's mark minted, gen's config.x ]` over N
# children `c1 .. cN` inheriting `a` (whose `x` states a default) and `d` inheriting the children
# forward and reversed.
#
# Residue, stated: the `mkType` result carries no foreign `key` (the caller owns that result), so
# nixpkgs' `lib.evalModules` collects `a` twice and refuses the doubled default, as on main.
#
# OQ-V3 on this arm: two constructions of one `mkType`-arm declaration (two schema evaluations) now
# meet at its node, where main's record-less arm composed both (`[k k]` for each pair): two
# constructions are refused by name (V→R, the default arm's OQ-V3 class), and one construction reached
# twice is one module (`[k k]` → `[k]`, the dedup the default arm already gives).
{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  T = genMerge.types;
  opt = t: genMerge.mkOption { type = t; };
  try =
    v:
    let
      r = builtins.tryEval (builtins.deepSeq v v);
    in
    if r.success then r.value else "REFUSED";
  mkTypeArm = {
    mkType =
      { defs, ... }:
      {
        __functor =
          _:
          { ... }:
          {
            imports = map (d: d.value) defs;
          };
      };
  };
  schemaOf =
    args: kinds:
    (genMerge.evalModuleTree { } [
      { options.schema = genSchema.mkSchemaOption args; }
      { config.schema = kinds; }
    ]).config.schema;
  diamondN =
    args: n: order:
    let
      cs = map (i: "c${toString i}") (lib.range 1 n);
      s = schemaOf args (
        {
          a.options.x = genMerge.mkOption {
            type = T.str;
            default = "d";
          };
        }
        // lib.genAttrs cs (c: {
          options."${c}o" = opt T.str;
          inherits = [ "a" ];
        })
        // {
          d = {
            options.w = opt T.str;
            inherits = if order == "fwd" then cs else lib.reverseList cs;
          };
        }
      );
      cfg.config = {
        w = "w";
      }
      // lib.genAttrs (map (c: "${c}o") cs) (o: o);
    in
    {
      inherit s cfg;
      row = [
        (try (builtins.isString s.d.__mint.minted))
        (try
          (genMerge.evalModuleTree { } [
            s.d
            cfg
          ]).config.x
        )
      ];
    };
  rowsOf =
    args:
    lib.concatMap (
      n:
      map (order: (diamondN args n order).row) [
        "fwd"
        "rev"
      ]
    ) (lib.range 2 4);
  # one declaration, two schema evaluations of the `mkType` arm, both imported into gen's engine
  twoConstructions =
    let
      decl = {
        options.trail = opt (T.listOf T.str);
        config.trail = [ "k" ];
      };
      a = (schemaOf mkTypeArm { k = decl; }).k;
      b = (schemaOf mkTypeArm { k = decl; }).k;
      sorted = v: if builtins.isList v then builtins.sort builtins.lessThan v else v;
      gen = ms: sorted (try (genMerge.evalModuleTree { } ms).config.trail);
    in
    {
      witnessEqual = a.__kindWitness == b.__kindWitness;
      ab = gen [
        a
        b
      ];
      aa = gen [
        a
        a
      ];
    };
in
{
  flake.tests.kind-mktype-diamond = {
    # N = 2..4 children, both orders: the shared ancestor's default is declared once
    test-mkType-diamond-at-N-children-composes-the-ancestor-once = {
      expr = rowsOf mkTypeArm;
      expected = lib.replicate 6 [
        true
        "d"
      ];
    };
    # the control: the default arm, the same rows
    test-default-arm-diamond-at-N-children-composes-the-ancestor-once = {
      expr = rowsOf { };
      expected = lib.replicate 6 [
        true
        "d"
      ];
    };
    # the residue, both trees: nixpkgs' engine collects the `mkType` arm's ancestor twice
    test-mkType-diamond-in-nixpkgs-engine-refuses-the-doubled-default = {
      expr =
        let
          d = diamondN mkTypeArm 2 "fwd";
        in
        try
          (lib.evalModules {
            modules = [
              d.s.d
              d.cfg
            ];
          }).config.x;
      expected = "REFUSED";
    };
    test-mkType-two-constructions-of-one-declaration-meet-at-its-node = {
      expr = twoConstructions;
      expected = {
        witnessEqual = true;
        ab = "REFUSED";
        aa = [ "k" ];
      };
    };
  };
}
