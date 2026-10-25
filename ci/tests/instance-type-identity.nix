# AN INSTANCE TYPE IS IDENTIFIED BY WHAT IT IS CONSTRUCTED FROM (den-hoag-dwln8, ADR-0034). The instance
# type mints over its constructor `gen-schema.instance`, the kind (a member, by its mark), `strict`
# (inert) and `extraModules` (sealed), never over the module list gen-schema writes from them. So
# instance types of different kinds mint apart, twins of one kind are one type, and a kind embedding an
# instance type, directly, under `attrsOf` or through a registry, reads the embedded kind in its mark.
# A self-referential instance type has no identity (ADR-0034's excluded populations) and is refused by
# name at gen-types' depth bound; the kinds around it still mint, guarded by the kind's `__okAt`.
#
# THE RESIDUE, pinned so a fix is visible (A10): an embedding option declared TWICE, or redeclared as a
# plain submodule, reaches the mark through gen-merge's union, which states nothing and seals the module
# list, so two such kinds embedding different kinds still share one mark and `kindEq` refuses.
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
        user = "schemakind:0258d16213206c7cacd5927961719ae699e70148d0fe6d2ba71ff678564d91f6";
        grp = "schemakind:8dedeeadc91d4e5e1f2845d770bafca6e9e0e0e9c6fc1d6e49a0f43430fc1357";
        hostStr = "schemakind:e27bf5dac712da7d5b54bbb410fd8c38544362d89ed58b7616d6eefd7c67928d";
        hostInt = "schemakind:0b9be9b995eb22cbfc2ac1e0e28ba838edfd342acad2cd085fe72dab05c33aa7";
        hostSub = "schemakind:44199e2176586913d3bee67018ee0efe4e7a060ba0d8faf84128cf579acfbb78";
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
        self = "schemakind:4c6287dfc0acdab89e55abc61d0421d09cae2cd6d49b8f37510546295f803098";
        mutualHost = "schemakind:9d4dbfc15a4614e2db4fbf2791b10522d4912b64e586ad426f1bdb0b41e92540";
        mutualUser = "schemakind:7a99a030586bccd64162065b044741fd8e546fe4f9aac769e2ed1e60412f2a5e";
        instance = [
          "1"
          "2"
          "host:94e7bbbbcf8fae27b8d069f841652ecb3a427f2cd2f59b9d4d66be6990195021"
        ];
      };
    };
    # a kind embedding a registry over itself mints too
    test-a8-a-kind-embedding-a-registry-over-itself-mints = {
      expr = selfRegS.host.__mint.minted;
      expected = "schemakind:bd1f5487fdab4dd3ded0e0a86bf9f1f8ad9ffc074cf40a00d39fcf1c87b7bd3d";
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
    # THE RESIDUE: the union route states nothing, so the marks collide and kindEq refuses
    test-a10-an-option-declared-twice-keeps-the-collision = {
      expr = {
        twiceMarksEqual = (twice tU).__mint.minted == (twice tG).__mint.minted;
        twiceKindEq = attempt (kindEq (twice tU) (twice tG));
        plusMarksEqual = (plus tU).__mint.minted == (plus tG).__mint.minted;
        plusKindEq = attempt (kindEq (plus tU) (plus tG));
      };
      expected = {
        twiceMarksEqual = true;
        twiceKindEq.success = false;
        plusMarksEqual = true;
        plusKindEq.success = false;
      };
    };
  };
}
