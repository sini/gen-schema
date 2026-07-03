# Codec either/oneOf dispatch — check-based branch selection, left-biased.
{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) mkSchemaOption mkInstanceRegistry mkCodec;

  eval = genMerge.evalModuleTree {
    modules = [
      {
        options.schema = mkSchemaOption { };
        options.items = mkInstanceRegistry eval.config.schema.item { };
        config.schema.item = {
          # either str int — distinguishable by isString / isInt
          options.value = genMerge.mkOption {
            type = genMerge.types.either genMerge.types.str genMerge.types.int;
          };
          # nullOr (either str int)
          options.optValue = genMerge.mkOption {
            type = genMerge.types.nullOr (genMerge.types.either genMerge.types.str genMerge.types.int);
            default = null;
          };
          # oneOf [ str int bool ] — desugars to nested either
          options.flexible = genMerge.mkOption {
            type = genMerge.types.oneOf [
              genMerge.types.str
              genMerge.types.int
              genMerge.types.bool
            ];
          };
          # either str (listOf int) — wrappers inside branches.
          # NB: gen-merge's `either` dispatches on the FIRST branch whose check is
          # definitive; a bare `listOf` has no discriminating check, so the total-check
          # branch (str) must come first. This preserves the same expected values.
          options.mixed = genMerge.mkOption {
            type = genMerge.types.either genMerge.types.str (genMerge.types.listOf genMerge.types.int);
          };
        };
        config.items.strItem = {
          value = "hello";
          flexible = "text";
          mixed = "plain";
        };
        config.items.intItem = {
          value = 42;
          flexible = 99;
          mixed = [
            1
            2
            3
          ];
        };
        config.items.boolItem = {
          value = "yes";
          optValue = 10;
          flexible = true;
          mixed = "fallback";
        };
      }
    ];
  };

  # Register a codec for int type
  codec = mkCodec eval.config.schema.item {
    types = {
      int = {
        encode = v: "n:${toString v}";
        decode = v: lib.toInt (lib.removePrefix "n:" v);
      };
    };
  };

  # No type registrations — identity for all branches
  identityCodec = mkCodec eval.config.schema.item { };
in
{
  flake.tests.codec-either = {
    # either: left branch (str) — no registered codec, identity
    test-either-left-identity = {
      expr = (identityCodec.encode eval.config.items.strItem).value;
      expected = "hello";
    };
    # either: right branch (int) — registered codec applies
    test-either-right-registered = {
      expr = (codec.encode eval.config.items.intItem).value;
      expected = "n:42";
    };
    # either: left branch (str) — str has no codec, identity
    test-either-left-no-codec = {
      expr = (codec.encode eval.config.items.strItem).value;
      expected = "hello";
    };

    # nullOr (either) — null
    test-nullor-either-null = {
      expr = (codec.encode eval.config.items.strItem).optValue;
      expected = null;
    };
    # nullOr (either) — int value
    test-nullor-either-int = {
      expr = (codec.encode eval.config.items.boolItem).optValue;
      expected = "n:10";
    };

    # oneOf — str branch
    test-oneof-str = {
      expr = (codec.encode eval.config.items.strItem).flexible;
      expected = "text";
    };
    # oneOf — int branch
    test-oneof-int = {
      expr = (codec.encode eval.config.items.intItem).flexible;
      expected = "n:99";
    };
    # oneOf — bool branch (no codec registered)
    test-oneof-bool = {
      expr = (codec.encode eval.config.items.boolItem).flexible;
      expected = true;
    };

    # either with wrappers inside branches: listOf int
    test-either-listof-branch = {
      expr = (codec.encode eval.config.items.intItem).mixed;
      expected = [
        "n:1"
        "n:2"
        "n:3"
      ];
    };
    # either with wrappers inside branches: str
    test-either-str-branch = {
      expr = (codec.encode eval.config.items.strItem).mixed;
      expected = "plain";
    };

    # Decode — identity codec round-trip
    test-identity-roundtrip = {
      expr =
        (identityCodec.decode {
          value = 42;
          flexible = "text";
          mixed = "plain";
        }).value;
      expected = 42;
    };
  };
}
