# AN INSTANCE TYPE IS IDENTIFIED BY WHAT IT IS CONSTRUCTED FROM (den-hoag-dwln8, ADR-0034). The instance
# type mints over its constructor `gen-schema.instance`, the kind (a member, by its mark), `strict`
# (inert) and `extraModules` (sealed), never over the module list gen-schema writes from them. So
# instance types of different kinds mint apart, twins of one kind are one type, and a kind embedding an
# instance type, directly, under `attrsOf` or through a registry, reads the embedded kind in its mark.
# A self-referential instance type has no identity (ADR-0034's excluded populations) and is refused by
# name at gen-types' depth bound; the kinds around it still mint, guarded by the kind's `__okAt`.
#
# An embedding option declared TWICE, or redeclared beside a plain submodule (A10), reaches the mark through
# gen-merge's union, which states its join (`gen-merge.submodule-join`, den-hoag-2vtgj) over the two
# declarations, each a member by its mark: two such kinds embedding different kinds read two marks, `kindEq`
# decides them, and the foreign key splits where the mark does. Instances of the two kinds holding the same
# data read two `id_hash`es; that reading keys off a kind mark whose `__sealed` is non-empty (the rebuilt
# module set), so where gen-schema's instance key comes to refuse such a mark, that cell moves to refused.
# A self-referential instance type declared twice joins a member with no identity, sealed by its own regime:
# its marks and `kindEq` answer, or refuse by name, and never abort.
{
  genSchema,
  genMerge,
  genAlgebra,
  ...
}:
let
  inherit (genSchema)
    evalSchema
    mkInstanceType
    mkInstanceRegistry
    kindEq
    ;
  T = genMerge.types;
  attempt =
    e:
    let
      r = builtins.tryEval (builtins.deepSeq e e);
    in
    if r.success then { inherit (r) success value; } else { success = false; };
  kA = evalSchema { } [
    {
      config.schema.user.options.uname = genMerge.mkOption { type = T.str; };
      config.schema.grp.options.gid = genMerge.mkOption { type = T.int; };
    }
  ];
  tU = mkInstanceType { } kA.user;
  tU2 = mkInstanceType { } kA.user;
  tG = mkInstanceType { } kA.grp;
  tUns = mkInstanceType { strict = false; } kA.user;
  digest = t: t.__mint.minted;
  extraA = {
    options.ply = genMerge.mkOption { default = 1; };
  };
  extraB = {
    options.nap = genMerge.mkOption { default = 2; };
  };
  hostOf = opt: (evalSchema { } [ { config.schema.host.options.owner = opt; } ]).host;
  direct = ty: genMerge.mkOption { type = ty; };
  shapes = {
    direct = k: direct (mkInstanceType { } k);
    attrsOf =
      k:
      genMerge.mkOption {
        type = T.attrsOf (mkInstanceType { } k);
        default = { };
      };
    registry = k: mkInstanceRegistry { } k;
  };
  extra = T.submodule { options.extra = genMerge.mkOption { default = ""; }; };
  twice =
    ty:
    (evalSchema { } [
      { config.schema.host.options.owner = direct ty; }
      { config.schema.host.options.owner = direct ty; }
    ]).host;
  plus =
    ty:
    (evalSchema { } [
      { config.schema.host.options.owner = direct ty; }
      { config.schema.host.options.owner = direct extra; }
    ]).host;
  selfS = evalSchema { } [
    (
      { config, ... }:
      {
        config.schema.host.options.addr = genMerge.mkOption { type = T.str; };
        config.schema.host.options.peer = genMerge.mkOption {
          type = T.nullOr (mkInstanceType { } config.schema.host);
          default = null;
        };
      }
    )
  ];
  selfRegS = evalSchema { } [
    (
      { config, ... }:
      {
        config.schema.host.options.addr = genMerge.mkOption { type = T.str; };
        config.schema.host.options.peers = mkInstanceRegistry { } config.schema.host;
      }
    )
  ];
  mutS = evalSchema { } [
    (
      { config, ... }:
      {
        config.schema.user.options.home = genMerge.mkOption {
          type = T.nullOr (mkInstanceType { } config.schema.host);
          default = null;
        };
        config.schema.host.options.owner = genMerge.mkOption {
          type = T.nullOr (mkInstanceType { } config.schema.user);
          default = null;
        };
      }
    )
  ];
  # instances holding the same data (`owner = null`), of a kind whose `owner` is declared twice
  nullOrTwice =
    ty:
    (evalSchema { } [
      {
        config.schema.host.options.owner = genMerge.mkOption { type = T.nullOr ty; };
      }
      {
        config.schema.host.options.owner = genMerge.mkOption { type = T.nullOr ty; };
      }
    ]).host;
  idHashOf =
    host:
    (genMerge.evalModuleTree { } [
      { options.h = genMerge.mkOption { type = mkInstanceType { } host; }; }
      {
        config.h.name = "a";
        config.h.owner = null;
      }
    ]).config.h.id_hash;
  redeclared = f: {
    marksEqual = (f tU).__mint.minted == (f tG).__mint.minted;
    kindEq = attempt (kindEq (f tU) (f tG));
    keyAgreesWithMark =
      ((f tU).__keyEq.key == (f tG).__keyEq.key) == ((f tU).__mint.minted == (f tG).__mint.minted);
  };
  twiceType =
    ty:
    (genMerge.evalModuleTree { } [
      { options.o = direct ty; }
      { options.o = direct ty; }
    ]).options.o.type;
  tSelf = mkInstanceType { } selfS.host;
  tSelf2 = mkInstanceType { } selfS.host;
  selfInst =
    (genMerge.evalModuleTree { } [
      { options.h = genMerge.mkOption { type = mkInstanceType { } selfS.host; }; }
      {
        config.h = {
          name = "a";
          addr = "1";
          peer = {
            name = "b";
            addr = "2";
          };
        };
      }
    ]).config.h;
in
{
  flake.tests.instance-type-identity = {
    test-a1-instance-types-of-two-kinds-mint-apart = {
      expr = digest tU != digest tG;
      expected = true;
    };
    test-a2-an-instance-type-is-not-the-bare-refusing-submodule = {
      expr = digest tU != digest (genMerge.refusingSubmodule null [ "config" "options" "prefix" ] { });
      expected = true;
    };
    test-a3-twins-of-one-kind-are-one-type = {
      expr = attempt (T.typeEq tU tU2);
      expected = {
        success = true;
        value = true;
      };
    };
    test-a4-strict-is-distinguishing = {
      expr = digest tU != digest tUns;
      expected = true;
    };
    test-a5-an-embedding-kind-reads-the-embedded-kind = {
      expr = builtins.mapAttrs (
        _: f: (hostOf (f kA.user)).__mint.minted != (hostOf (f kA.grp)).__mint.minted
      ) shapes;
      expected = {
        direct = true;
        attrsOf = true;
        registry = true;
      };
    };
    test-a6-kindeq-decides-the-two-embedding-kinds = {
      expr = attempt (kindEq (hostOf (shapes.direct kA.user)) (hostOf (shapes.direct kA.grp)));
      expected = {
        success = true;
        value = false;
      };
    };
    # the control: kinds and types embedding no instance type are unmoved, and owner : str vs int separate
    test-a7-control-kinds-embedding-no-instance-type-are-unmoved = {
      expr = {
        user = kA.user.__mint.minted;
        grp = kA.grp.__mint.minted;
        hostStr = (hostOf (direct T.str)).__mint.minted;
        hostInt = (hostOf (direct T.int)).__mint.minted;
        hostSub = (hostOf (direct (T.submodule { }))).__mint.minted;
        submodule = digest (T.submodule { });
      };
      expected = {
        user = "schemakind:c4c1e8f08a3c525775b92f4ba75ffb2d1ab60013a66b49c293e02e9416955b0a";
        grp = "schemakind:29bccb712d8dc47aa53887815e73e1dbd8941c562dc2d5467f2eb44176a9ac97";
        hostStr = "schemakind:1dd572bd8c8837079005bf42279ed75d7d9d311e365eb59f165e1e66513aab44";
        hostInt = "schemakind:f83d147b774fc7ea457339e36b8765f6a3e8bdd8e8cc29066534f72f67f457dd";
        hostSub = "schemakind:88d7b6e856db4c8e62675ed8999c514aa72f86b89b16573de922ff626ea3694a";
        submodule = "type:155fcba8d4e089844a5e5371bc1c52651ca44d1353e6b3b155e4b3940f437baf";
      };
    };
    test-a8-self-and-mutually-referential-kinds-mint = {
      expr = {
        self = selfS.host.__mint.minted;
        mutualHost = mutS.host.__mint.minted;
        mutualUser = mutS.user.__mint.minted;
        instance = [
          selfInst.addr
          selfInst.peer.addr
          selfInst.id_hash
        ];
      };
      expected = {
        self = "schemakind:8f856f8224a8ace98403a096889198a1cc611d310bbc1d8c309bfb92cf21b00b";
        mutualHost = "schemakind:5342285ce63a741f4c681748ebd48118c4b2739e4ec1370e5d6ada91f7d4548a";
        mutualUser = "schemakind:c29cf1efd9fbb086dc46ae99410fee893822e2682912d3e7eb467527a5693fef";
        instance = [
          "1"
          "2"
          "host:01134493456f59afc53e37ce0f433d84be01b931b26125f498722620748f13f1"
        ];
      };
    };
    # a kind embedding a registry over itself mints too
    test-a8-a-kind-embedding-a-registry-over-itself-mints = {
      expr = selfRegS.host.__mint.minted;
      expected = "schemakind:41069a9427a5e7221e0a0543f6ea853d0220c96e19d5147b13fe2bd505aa8022";
    };
    test-a8-a-self-referential-instance-type-has-no-identity = {
      expr = (mkInstanceType { } selfS.host).__mint;
      expected = {
        unmintable = {
          ctor = "gen-schema.instance";
          reason = "a type nests deeper than the type-identity depth bound (128 levels); a self-referential type has no identity";
        };
      };
    };
    # `extraModules` is distinguishing and sealed: an instance type with them is apart from one without
    # (its mark tags the component), and two differing only in them are refused, never one type
    test-a11-extra-modules-are-distinguishing-and-sealed = {
      expr = {
        withAndWithout = attempt (T.typeEq (mkInstanceType { extraModules = [ extraA ]; } kA.user) tU);
        twoSets = attempt (
          T.typeEq (mkInstanceType { extraModules = [ extraA ]; } kA.user) (
            mkInstanceType { extraModules = [ extraB ]; } kA.user
          )
        );
        tagIsSealedMarker = { sealed = true; } == genAlgebra.sealedMarker;
      };
      expected = {
        withAndWithout = {
          success = true;
          value = false;
        };
        twoSets.success = false;
        tagIsSealedMarker = true;
      };
    };
    test-a10-an-option-declared-twice-reads-the-embedded-kind = {
      expr = {
        twice = redeclared twice;
        plus = redeclared plus;
        nullOrTwiceIdHashesEqual = idHashOf (nullOrTwice tU) == idHashOf (nullOrTwice tG);
      };
      expected = {
        twice = {
          marksEqual = false;
          kindEq = {
            success = true;
            value = false;
          };
          keyAgreesWithMark = true;
        };
        plus = {
          marksEqual = false;
          kindEq = {
            success = true;
            value = false;
          };
          keyAgreesWithMark = true;
        };
        nullOrTwiceIdHashesEqual = false;
      };
    };
    # a self-referential instance type declared twice: its join's first member has no identity, so it is sealed
    # by its own regime. Its kind still mints apart from another embedding kind's; twins are refused by name, and
    # their joined types read `false`, as two separately built self-referential types read alone (A8), and so do two
    # joins of one binding built in two evaluations
    test-a10-a-self-referential-instance-type-declared-twice-never-aborts = {
      expr = {
        marksApart = attempt ((twice tSelf).__mint.minted != (twice tU).__mint.minted);
        kindEqApart = attempt (kindEq (twice tSelf) (twice tU));
        kindEqTwins = attempt (kindEq (twice tSelf) (twice tSelf2));
        typeEqTwins = attempt (T.typeEq (twiceType tSelf) (twiceType tSelf2));
        typeEqSameBinding = attempt (T.typeEq (twiceType tSelf) (twiceType tSelf));
        loneTypeEqTwins = attempt (T.typeEq tSelf tSelf2);
      };
      expected = {
        marksApart = {
          success = true;
          value = true;
        };
        kindEqApart = {
          success = true;
          value = false;
        };
        kindEqTwins.success = false;
        typeEqTwins = {
          success = true;
          value = false;
        };
        typeEqSameBinding = {
          success = true;
          value = false;
        };
        loneTypeEqTwins = {
          success = true;
          value = false;
        };
      };
    };
  };
}
