# A refined type redeclared over bases its base relation JOINS into a third type (a union: a
# `submodule`'s option sets, an `enum`'s members). The refinement re-applies over the base relation's
# answer, so neither declaration's base is dropped, in either presentation order, and a refined
# pair answers what its bare pair answers with the refinements on top.
{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  t = genMerge.types;
  nt = lib.types;
  inherit (genSchema) refined refinements;
  r = [ refinements.positive ];
  R = b: refined b r;

  subA = t.submodule {
    options.a = genMerge.mkOption {
      type = t.str;
      default = "d";
    };
  };
  subB = t.submodule {
    options.b = genMerge.mkOption {
      type = t.int;
      default = 0;
    };
  };

  valueOf =
    tA: tB: v:
    let
      attempt = builtins.tryEval (
        let
          c =
            (genMerge.evalModuleTree {
              modules = [
                { options.p = genMerge.mkOption { type = tA; }; }
                { options.p = genMerge.mkOption { type = tB; }; }
                { p = v; }
              ];
            }).config.p;
        in
        builtins.deepSeq c c
      );
    in
    if attempt.success then attempt.value else "refused";

  typeOf =
    tA: tB:
    (genMerge.evalModuleTree {
      modules = [
        { options.p = genMerge.mkOption { type = tA; }; }
        { options.p = genMerge.mkOption { type = tB; }; }
      ];
    }).options.p.type;

  between = nt.ints.between 0 1;

  # A GEN-NATIVE relation that renames on every successful join, over three declarations whose OWN
  # names all differ from each other and from the joined answer — unlike a nixpkgs check family
  # (`port`, `ints.between`), which the witness now refuses rather than renames past both operands'
  # names (`lib/refined.nix`'s header). A name gate comparing `baseType.name` across the fold would
  # refuse at the first step, where the real relation (asked structurally, through `mergeTypes`)
  # legitimately renames and keeps folding.
  renamed = {
    name = "renamed";
    typeMergeRel =
      other:
      if
        builtins.elem (other.name or null) [
          "renameA"
          "renameB"
          "renameC"
          "renamed"
        ]
      then
        { merged = renamed; }
      else
        { refused = "types do not merge: 'renamed' and '${other.name or "<unnamed>"}'"; };
  };
  renameA = {
    name = "renameA";
    typeMergeRel =
      other: if (other.name or null) == "renameB" then { merged = renamed; } else { refused = "no"; };
  };
  renameB = {
    name = "renameB";
    typeMergeRel =
      other: if (other.name or null) == "renameA" then { merged = renamed; } else { refused = "no"; };
  };
  renameC = {
    name = "renameC";
    typeMergeRel =
      other: if (other.name or null) == "renamed" then { merged = renamed; } else { refused = "no"; };
  };
in
{
  flake.tests.refined-union = {
    test-union-keeps-the-earlier-submodule-options = {
      expr = valueOf (R subA) (R subB) { b = 1; };
      expected = {
        a = "d";
        b = 1;
      };
    };
    test-union-keeps-the-earlier-submodule-options-other-order = {
      expr = valueOf (R subB) (R subA) { b = 1; };
      expected = {
        a = "d";
        b = 1;
      };
    };
    test-union-keeps-the-earlier-enum-member = {
      expr = map (o: (typeOf (R (nt.enum [ o.a ])) (R (nt.enum [ o.b ]))).check o.a) [
        {
          a = "a";
          b = "b";
        }
        {
          a = "b";
          b = "a";
        }
      ];
      expected = [
        true
        true
      ];
    };
    test-union-keeps-the-refinements = {
      expr = map (x: x.message) (typeOf (R subA) (R subB)).__schema.refinements;
      expected = [ refinements.positive.message ];
    };
    # A shared value's fold stays closed: three declarations of ONE shared `between` value, whose
    # bare fold keeps the operand (gen-merge's sealed-limb twin), so the refined fold stays closed
    # and keeps `intBetween` with its refinements. This construction never renames (all three
    # declarations, and the joined answer, already share one name), so it cannot tell a name gate
    # apart from no gate at all — see the row below for that.
    test-a-shared-value-fold-stays-closed-over-three-declarations = {
      expr =
        let
          attempt = builtins.tryEval (
            let
              ty =
                (genMerge.evalModuleTree {
                  modules = [
                    { options.p = genMerge.mkOption { type = R between; }; }
                    { options.p = genMerge.mkOption { type = R between; }; }
                    { options.p = genMerge.mkOption { type = R between; }; }
                    { p = 1; }
                  ];
                }).options.p.type;
              v = {
                inherit (ty) name;
                refinements = map (x: x.message) ty.__schema.refinements;
              };
            in
            builtins.deepSeq v v
          );
        in
        if attempt.success then attempt.value else "refused";
      expected = {
        name = "intBetween";
        refinements = [ refinements.positive.message ];
      };
    };

    # Guard on the relation having no name gate, over three declarations that DO rename: `renameA`
    # and `renameB` share no name with each other or with their joined answer, and `renameC` shares
    # no name with that answer either. `relation` (`lib/refined.nix`) asks `mergeTypes` structurally
    # and never compares `baseType.name` to the partner's, so the fold stays closed and renames
    # twice, keeping the refinements. A `baseType.name`-keyed gate would refuse at the first join,
    # where `renameA' and `renameB' disagree.
    test-a-renaming-join-stays-closed-over-three-declarations = {
      expr =
        let
          step1 = (R renameA).typeMerge { type = R renameB; };
          step2 = if step1 == null then null else step1.typeMerge { type = R renameC; };
        in
        if step2 == null then
          "refused"
        else
          {
            name = step2.__schema.baseType.name;
            refinements = map (x: x.message) step2.__schema.refinements;
          };
      expected = {
        name = "renamed";
        refinements = [ refinements.positive.message ];
      };
    };
    test-a-refined-twin-answers-what-its-bare-twin-answers = {
      expr = (typeOf (R between) (R between)).check 5;
      expected = (typeOf between between).check 5;
    };
  };
}
