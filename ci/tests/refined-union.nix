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
    # Guard on the relation having no name gate: three declarations of ONE shared `between` value,
    # whose bare fold keeps the operand (gen-merge's sealed-limb twin), so the refined fold stays
    # closed and keeps `intBetween` with its refinements.
    test-a-renaming-join-stays-closed-over-three-declarations = {
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
    test-a-refined-twin-answers-what-its-bare-twin-answers = {
      expr = (typeOf (R between) (R between)).check 5;
      expected = (typeOf between between).check 5;
    };
  };
}
