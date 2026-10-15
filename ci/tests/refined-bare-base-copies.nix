# A refined declaration beside its own bare base, where one of the two is a COPY carrying a check beyond
# its functor (a `//` copy, `addCheck`, either re-doored or raw). `refined int [> 3]` and `int` meet to the
# refinement (`{v:B | e} ⊓ B = {v:B | e}`); each copy below also rejects 5. Every row lists what
# `x = 4`, `x = 5` and `x = 3` read (`R` is refused), copy declared first (`copyFirst`) and second
# (`copySecond`).
#
# ★ THE MEET KEEPS THE COPY'S DECLARATION. Where nixpkgs' engine hands gen's bare `int` the refined copy's
# functor, gen defers to the refined relation and meets its answer with the copy's own declaration
# (`functor.__declared`, the slot a re-doored `verify` copy states), as the name-matching arm does. Without
# that meet the deferral answers the refined record bare and 5 is served.
#
# ★ THE REST OF THE NIXPKGS-ENGINE ROWS SERVE 5, AND EACH IS PINNED HERE AS THE SHAPE IT IS:
# - a re-doored `addCheck` or `check` copy declared first: its functor carries no `__declared`, so the
#   check never reaches gen and nixpkgs' merge drops it. That is nixpkgs' drop, Not covered (den-hoag-xdvta,
#   half 1, arm N). The same copy beside its own original serves 5 too.
# - a raw `addCheck` or `check` copy, either order: PROVISIONAL on the open classification of a raw copy
#   under nixpkgs' engine (den-hoag-f66c6, S′). The same copy beside its own original serves 5 too. If that
#   ruling refuses them, these rows flip.
# - a raw `verify` copy: nixpkgs' engine never reads `verify`, so the copy declared alone serves 5.
# gen's engine reads every row as the meet: 4 served, 5 and 3 refused.
{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  gt = genMerge.types;
  R = genSchema.refined gt.int [
    {
      check = v: v > 3;
      message = "must be above 3";
    }
  ];
  copies = {
    addCheck = ty: lib.types.addCheck ty (v: v != 5);
    verify =
      ty:
      ty
      // {
        verify = v: if v == 5 then "is 5" else ty.verify v;
      };
    check =
      ty:
      ty
      // {
        check = v: ty.check v && v != 5;
      };
  };
  doors = {
    raw = ty: ty;
    defineType = gt.defineType;
    mkOptionType = genMerge.mkOptionType;
  };
  read =
    engine: ts: v:
    let
      mods =
        map (ty: { options.x = (if engine == "gen" then genMerge else lib).mkOption { type = ty; }; }) ts
        ++ [
          { x = v; }
        ];
      x =
        if engine == "gen" then
          (genMerge.evalModuleTree { } mods).config.x
        else
          (lib.evalModules { modules = mods; }).config.x;
      r = builtins.tryEval (builtins.deepSeq x x);
    in
    if r.success then toString r.value else "R";
  values =
    engine: ts:
    lib.concatMapStringsSep "," (read engine ts) [
      4
      5
      3
    ];
  # `side` names which declaration is the copy: the refined one (beside `int`) or the bare one (beside `R`)
  row =
    side: copy: door: engine:
    let
      c = doors.${door} (copies.${copy} (if side == "refined" then R else gt.int));
      other = if side == "refined" then gt.int else R;
    in
    {
      copyFirst = values engine [
        c
        other
      ];
      copySecond = values engine [
        other
        c
      ];
    };
  met = {
    copyFirst = "4,R,R";
    copySecond = "4,R,R";
  };
  dropsFirst = {
    copyFirst = "4,5,R";
    copySecond = "4,R,R";
  };
  dropsBoth = {
    copyFirst = "4,5,R";
    copySecond = "4,5,R";
  };
  grid =
    engine: copyNames: doorNames:
    lib.concatMap
      (
        side:
        lib.concatMap (
          copy: map (door: lib.nameValuePair "${side}-${copy}-${door}" (row side copy door engine)) doorNames
        ) copyNames
      )
      [
        "refined"
        "bare"
      ];
  each = engine: copyNames: doorNames: expected: {
    expr = builtins.listToAttrs (grid engine copyNames doorNames);
    expected = builtins.listToAttrs (
      map (p: p // { value = expected; }) (grid engine copyNames doorNames)
    );
  };
in
{
  flake.tests.refined-bare-base-copies = {
    test-a-re-doored-verify-copy-of-either-declaration-keeps-its-verify-in-nixpkgs-engine =
      each "nixpkgs" [ "verify" ] [ "defineType" "mkOptionType" ]
        met;
    test-every-copy-meets-in-gens-engine =
      each "gen" (builtins.attrNames copies) (builtins.attrNames doors)
        met;
    test-not-covered-a-re-doored-addcheck-or-check-copy-declared-first-is-dropped-by-nixpkgs-merge =
      each "nixpkgs" [ "addCheck" "check" ] [ "defineType" "mkOptionType" ]
        dropsFirst;
    test-provisional-a-raw-addcheck-or-check-copy-is-unclassified-in-nixpkgs-engine =
      each "nixpkgs" [ "addCheck" "check" ] [ "raw" ]
        dropsBoth;
    test-a-raw-verify-copy-is-inert-in-nixpkgs-engine = each "nixpkgs" [ "verify" ] [ "raw" ] dropsBoth;
    # the reference each row is read against: the copy declared alone enforces its check in both engines,
    # except a raw `verify` copy in nixpkgs' engine, which never reads `verify`
    test-control-each-copy-declared-alone-refuses-5 = {
      expr = lib.concatMap (
        copy:
        lib.concatMap (
          door:
          map (engine: "${copy} ${door} ${engine} ${values engine [ (doors.${door} (copies.${copy} R)) ]}") [
            "gen"
            "nixpkgs"
          ]
        ) (builtins.attrNames doors)
      ) (builtins.attrNames copies);
      expected = lib.concatMap (
        copy:
        lib.concatMap (
          door:
          map
            (
              engine:
              "${copy} ${door} ${engine} ${
                if copy == "verify" && door == "raw" && engine == "nixpkgs" then "4,5,R" else "4,R,R"
              }"
            )
            [
              "gen"
              "nixpkgs"
            ]
        ) (builtins.attrNames doors)
      ) (builtins.attrNames copies);
    };
  };
}
