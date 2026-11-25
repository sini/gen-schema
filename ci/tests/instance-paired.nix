# THE PAIRED SIBLING (den-hoag-t5ndo 1b H1). `mkInstancePaired opts kind` takes mkInstanceType's closed
# options and its kind and returns `{ type; evaluate; }` from ONE construction (gen-merge
# `refusingSubmodulePaired`): `type` is the construction mkInstanceType makes from the same inputs, and
# `evaluate loc defs` is one evaluation of it, `{ config; provenance; }`. These cells pin the pair's shape, that
# its config is its own typed merge's and mkInstanceType's on the same inputs (two constructions, never one
# evaluation), that each pair reports its own kind, that no derived value carries an evaluator, that provenance
# is served beside a poisoned sibling, and that mkInstanceType itself is unchanged in kind.
{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  gm = genMerge;
  gt = gm.types;
  schema = genSchema.evalSchema { } [
    {
      config.schema.host = {
        options.a = gm.mkOption {
          type = gt.int;
          default = 0;
        };
        options.addr = gm.mkOption {
          type = gt.str;
          default = "x";
        };
        options.ls = gm.mkOption {
          type = gt.listOf gt.str;
          default = [ "base" ];
        };
      };
      config.schema.open = {
        freeformType = gt.lazyAttrsOf gt.raw;
        options.a = gm.mkOption {
          type = gt.int;
          default = 0;
        };
      };
      config.schema.other = {
        options.b = gm.mkOption {
          type = gt.int;
          default = 7;
        };
      };
    }
  ];
  kind = schema.host;
  P = genSchema.mkInstancePaired { } kind;
  PS = genSchema.mkInstancePaired { strict = true; } kind;
  Q = genSchema.mkInstancePaired { } schema.other;
  F = genSchema.mkInstancePaired { } schema.open;
  T = genSchema.mkInstanceType { } kind;
  TS = genSchema.mkInstanceType { strict = true; } kind;
  loc = [
    "users"
    "tux"
  ];
  try =
    e:
    let
      r = builtins.tryEval (builtins.deepSeq e e);
    in
    if r.success then r.value else "refused";
  own = c: removeAttrs c [ "_identityKeys" ];
  rows = {
    plain = [
      {
        file = "d.nix";
        value.a = 1;
      }
    ];
    freeform = [
      {
        file = "d.nix";
        value = {
          a = 1;
          extra = "e";
        };
      }
    ];
    two = [
      {
        file = "d1.nix";
        value = {
          a = 1;
          ls = [ "x" ];
        };
      }
      {
        file = "d2.nix";
        value = {
          addr = "y";
          ls = [ "y" ];
        };
      }
    ];
    named = [
      {
        file = "d.nix";
        value.name = "other";
      }
    ];
    wrongType = [
      {
        file = "d.nix";
        value.a = "str";
      }
    ];
    forced = [
      {
        file = "d1.nix";
        value.a = lib.mkForce 3;
      }
      {
        file = "d2.nix";
        value.a = 4;
      }
    ];
    argName = [
      {
        file = "d.nix";
        value._module.args.name = "argn";
      }
    ];
    outOfDomain = [
      {
        file = "d.nix";
        value = 5;
      }
    ];
    empty = [ ];
  };
  parity =
    p: t:
    builtins.mapAttrs (_: defs: {
      own = try (own (p.evaluate loc defs).config) == try (own (p.type.merge loc defs));
      legacy = try (own (p.evaluate loc defs).config) == try (own (t.merge loc defs));
    }) rows;
  allTrue = builtins.mapAttrs (_: _: {
    own = true;
    legacy = true;
  }) rows;
  isPair = v: builtins.isAttrs v && v ? evaluate;
in
{
  flake.tests.instance-paired = {
    test-the-pair-and-its-result-have-their-stated-shape = {
      expr = {
        pair = builtins.attrNames P;
        result = builtins.attrNames (P.evaluate loc rows.plain);
      };
      expected = {
        pair = [
          "evaluate"
          "type"
        ];
        result = [
          "config"
          "provenance"
        ];
      };
    };
    test-the-evaluators-config-is-its-typed-merges-and-mkinstancetypes-lax = {
      expr = parity P T;
      expected = allTrue;
    };
    test-the-evaluators-config-is-its-typed-merges-and-mkinstancetypes-strict = {
      expr = parity PS TS;
      expected = allTrue;
    };
    # The parity's control: the rows serve and refuse as stated, so the equalities are not refusals throughout.
    test-the-rows-serve-and-refuse-as-stated = {
      expr = {
        lax = builtins.mapAttrs (_: defs: try (P.evaluate loc defs).config != "refused") rows;
        strictFreeform = try (PS.evaluate loc rows.freeform).config != "refused";
      };
      expected = {
        lax = {
          plain = true;
          freeform = false;
          two = true;
          named = true;
          wrongType = false;
          forced = true;
          argName = false;
          outOfDomain = false;
          empty = true;
        };
        strictFreeform = false;
      };
    };
    test-the-pairs-type-is-mkinstancetypes-construction = {
      expr = gt.typeEq P.type T;
      expected = true;
    };
    test-each-pair-evaluates-its-own-kind = {
      expr = {
        pA = (P.evaluate loc rows.plain).config.a;
        pHasB = (P.evaluate loc rows.plain).config ? b;
        qB = (Q.evaluate loc [ ]).config.b;
        qHasA = (Q.evaluate loc [ ]).config ? a;
      };
      expected = {
        pA = 1;
        pHasB = false;
        qB = 7;
        qHasA = false;
      };
    };
    test-no-derived-or-edited-value-carries-an-evaluator = {
      expr = {
        withArgs = isPair (P.type.withArgs { });
        edited = isPair (P.type // { check = _: true; });
        genAttrsElem = isPair (gt.attrsOf P.type).nestedTypes.elemType;
        nixpkgsAttrsElem = isPair (lib.types.attrsOf P.type).nestedTypes.elemType;
        onTheType = P.type ? evaluate;
        onMkInstanceType = T ? evaluate;
      };
      expected = {
        withArgs = false;
        edited = false;
        genAttrsElem = false;
        nixpkgsAttrsElem = false;
        onTheType = false;
        onMkInstanceType = false;
      };
    };
    # A type handed where the kind belongs is refused at `evaluate`, as mkInstanceType refuses it at its merge; the
    # pair itself stays lazy.
    test-a-type-in-the-kinds-place-is-refused-where-it-is-read = {
      expr = {
        whnf = (builtins.tryEval (builtins.attrNames (genSchema.mkInstancePaired { } T))).success;
        evaluate = try ((genSchema.mkInstancePaired { } T).evaluate loc rows.plain).config;
        legacy = try ((genSchema.mkInstanceType { } T).merge loc rows.plain);
      };
      expected = {
        whnf = true;
        evaluate = "refused";
        legacy = "refused";
      };
    };
    test-the-typed-merge-stays-a-plain-function = {
      expr = {
        pairFn = builtins.isFunction P.type.merge;
        pairArgs = builtins.functionArgs P.type.merge;
        legacyFn = builtins.isFunction T.merge;
        legacyArgs = builtins.functionArgs T.merge;
      };
      expected = {
        pairFn = true;
        pairArgs = { };
        legacyFn = true;
        legacyArgs = { };
      };
    };
    # Q2 / G7: a poisoned freeform sibling leaves the result lazy: the declared option's value and its provenance,
    # and the poisoned sibling's provenance, are served; only the poisoned value refuses.
    test-provenance-is-served-beside-a-poisoned-freeform-sibling = {
      expr =
        let
          r = F.evaluate loc [
            {
              file = "d.nix";
              value = {
                a = 1;
                zz = throw "POISON";
              };
            }
          ];
        in
        {
          a = r.config.a;
          aFiles = map (d: d.file) r.provenance.a.defs;
          zzFiles = map (d: d.file) r.provenance.zz.defs;
          zz = (builtins.tryEval r.config.zz).success;
        };
      expected = {
        a = 1;
        aFiles = [
          "<default>"
          "d.nix"
        ];
        zzFiles = [ "d.nix" ];
        zz = false;
      };
    };
  };
}
