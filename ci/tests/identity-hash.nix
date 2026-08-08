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
      genTyped = (mkFloatEval genFloatOpt 1.5).config.id_hash == (mkFloatEval genFloatOpt 2.5).config.id_hash;
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
}
