{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) mkIdentityModule;
  mkEval =
    kind: modules:
    genMerge.evalModuleTree {
      modules = [ (mkIdentityModule kind) ] ++ modules;
    };

  evalA = mkEval "host" [
    { options.name = genMerge.mkOption { type = genMerge.types.str; }; }
    { config.name = "igloo"; }
  ];
  evalB = mkEval "host" [
    { options.name = genMerge.mkOption { type = genMerge.types.str; }; }
    { config.name = "igloo"; }
  ];
  evalC = mkEval "host" [
    { options.name = genMerge.mkOption { type = genMerge.types.str; }; }
    { config.name = "castle"; }
  ];

  # Identity reflection must also cover NIXPKGS-typed options (`lib.types.str`, whose type name is
  # "str", not gen-types' "string"): den declares every entity option with nixpkgs `lib.types`, so a
  # nixpkgs-str identity field (e.g. a home's `system`) must be reflected — else two instances that
  # differ only in it collapse to one id_hash (den's multi-system `home:ben` regression).
  evalNixStrA = mkEval "host" [
    { options.system = lib.mkOption { type = lib.types.str; }; }
    { config.system = "aarch64-linux"; }
  ];
  evalNixStrB = mkEval "host" [
    { options.system = lib.mkOption { type = lib.types.str; }; }
    { config.system = "x86_64-linux"; }
  ];

  # A FLOAT-typed option is a declared field two instances can differ in, so it is an identity key
  # like any other primitive — and both type systems spell the type name "float". Admitting it is
  # what the `==`-as-reference rule implies; the encoder's strict domain is what makes it safe.
  mkFloatEval =
    mkOpt: value:
    mkEval "host" [
      { options.load = mkOpt; }
      { config.load = value; }
    ];
  genFloatOpt = genMerge.mkOption { type = genMerge.types.float; };
  nixFloatOpt = lib.mkOption { type = lib.types.float; };

  # den-hoag-376hw. A leading underscore is not a reservation in FIELD space: the schema's
  # reserved-name mechanism ranges over KIND names (`lib/entry-type.nix`, `reservedKindNames`),
  # while a kind's own options are discriminated by the `internal = true` flag -- the same marker
  # `docs.nix` and `codec.nix` already read. A declared, non-`internal`, primitive `_legacyId` is
  # distinguishing content and must enter the preimage; before the prefix clause left
  # `isPrimitiveOption` these two instances hashed identically, and identically to
  # `evalNoUnderscore` below, which never declares the field at all.
  mkUnderscoreEval =
    legacyOpt: legacyValue:
    mkEval "host" [
      {
        options.name = genMerge.mkOption { type = genMerge.types.str; };
        options.addr = genMerge.mkOption { type = genMerge.types.str; };
        options._legacyId = legacyOpt;
      }
      {
        config.name = "igloo";
        config.addr = "10.0.0.1";
        config._legacyId = legacyValue;
      }
    ];
  underscoreOpt = genMerge.mkOption { type = genMerge.types.str; };
  underscoreInternalOpt = genMerge.mkOption {
    type = genMerge.types.str;
    internal = true;
  };

  # The same kind with NO underscore field -- the arm that proves the reflection change disturbs
  # nothing else. Its hash is pinned as a literal, not compared to a sibling: a comparison between
  # two things the same edit moves cannot see them both move.
  evalNoUnderscore = mkEval "host" [
    {
      options.name = genMerge.mkOption { type = genMerge.types.str; };
      options.addr = genMerge.mkOption { type = genMerge.types.str; };
    }
    {
      config.name = "igloo";
      config.addr = "10.0.0.1";
    }
  ];
in
{
  flake.tests.identity-hash.test-same-entity-same-hash = {
    expr = evalA.config.id_hash == evalB.config.id_hash;
    expected = true;
  };
  flake.tests.identity-hash.test-different-entity-different-hash = {
    expr = evalA.config.id_hash == evalC.config.id_hash;
    expected = false;
  };
  flake.tests.identity-hash.test-hash-is-string = {
    expr = builtins.isString evalA.config.id_hash;
    expected = true;
  };
  # The ruled shape: a kind tag joined to a 64-hex digest. The length assertion is on the DIGEST
  # REGION — past the first colon — because the identity is the tag AND the digest, and a bare 64
  # would pin only half of it.
  flake.tests.identity-hash.test-hash-shape = {
    expr = {
      wholeIdentity = builtins.match "host:[0-9a-f]{64}" evalA.config.id_hash != null;
      digestRegionLength = builtins.stringLength (builtins.substring 5 (-1) evalA.config.id_hash);
    };
    expected = {
      wholeIdentity = true;
      digestRegionLength = 64;
    };
  };
  # nixpkgs-str identity field is reflected: instances differing only in it hash differently.
  flake.tests.identity-hash.test-nixpkgs-str-field-reflected = {
    expr = evalNixStrA.config.id_hash == evalNixStrB.config.id_hash;
    expected = false;
  };

  # A float-typed field is reflected, under EITHER type system's spelling of the type.
  flake.tests.identity-hash.test-float-field-reflected = {
    expr = {
      genTyped =
        (mkFloatEval genFloatOpt 1.5).config.id_hash == (mkFloatEval genFloatOpt 2.5).config.id_hash;
      nixpkgsTyped =
        (mkFloatEval nixFloatOpt 1.5).config.id_hash == (mkFloatEval nixFloatOpt 2.5).config.id_hash;
      # …and it merges with the `==`-equal int, which is the whole point of admitting it: the
      # reference relation is the language's, so `1.0` and `1` are ONE value in an identity
      # position even though `toJSON` renders them differently.
      integralFloatMergesWithInt =
        (mkFloatEval genFloatOpt 2.0).config.id_hash
        == (mkFloatEval (genMerge.mkOption { type = genMerge.types.int; }) 2).config.id_hash;
    };
    expected = {
      genTyped = false;
      nixpkgsTyped = false;
      integralFloatMergesWithInt = true;
    };
  };

  # The strict |v| < 2^53 domain is now reachable from an ordinary declaration, so its refusal is a
  # USER-VISIBLE error at mint time rather than an internal guard — and it refuses by name, which is
  # what makes it catchable at all.
  flake.tests.identity-hash.test-float-field-outside-domain-refused-at-mint = {
    expr = (builtins.tryEval (mkFloatEval genFloatOpt 9007199254740992.0).config.id_hash).success;
    expected = false;
  };
  flake.tests.identity-hash.test-control-float-field-inside-domain-admitted = {
    expr = (builtins.tryEval (mkFloatEval genFloatOpt 9007199254740991.0).config.id_hash).success;
    expected = true;
  };

  # A `_`-prefixed field is reflected when it is a declared, non-`internal` primitive: two instances
  # differing only in it hash differently.
  flake.tests.identity-hash.test-underscore-nonint-field-reflected = {
    expr =
      (mkUnderscoreEval underscoreOpt "A").config.id_hash == (mkUnderscoreEval underscoreOpt "B")
      .config.id_hash;
    expected = false;
  };
  # Control: the SAME field marked `internal = true` is excluded -- the flag is what discriminates,
  # and it exercises the predicate at an input the cell above never reaches.
  flake.tests.identity-hash.test-control-underscore-internal-field-not-reflected = {
    expr =
      (mkUnderscoreEval underscoreInternalOpt "A").config.id_hash
      == (mkUnderscoreEval underscoreInternalOpt "B").config.id_hash;
    expected = true;
  };
  # Control: a kind with no underscore field anywhere hashes to a pinned literal, byte-identical
  # across the reflection change. This is the blast-radius arm -- an already-minted identity that
  # moved would red here.
  flake.tests.identity-hash.test-control-no-underscore-field-hash-unchanged = {
    expr = evalNoUnderscore.config.id_hash;
    expected = "host:813217e3cf0b6bc979121615b67c75532bc05e7742b0b5ebf9897a14aa8a6e43";
  };
}
