# The constant component tags (den-hoag-a7c9r U1): gen-algebra mints the `null` and `[ ]` tags once per
# partial application and this library shares one partial, so every kind's absent function, empty
# collection and `null` default enter its mark by one shared tag. Byte identity is the claim: the marks
# of a three-kind chain, read before the sharing, pinned verbatim. `b` and `c` are parented, so their
# marks moved once with U2 (a parent enters by its own mark), and are re-pinned as measured; `a`, the
# parentless one, is unmoved.
{
  genSchema,
  genMerge,
  ...
}:
let
  T = genMerge.types;
  schema =
    (genMerge.evalModuleTree { } [
      { options.schema = genSchema.mkSchemaOption { }; }
      {
        config.schema = {
          a.options.x = genMerge.mkOption { type = T.str; };
          b = {
            inherits = [ "a" ];
            options.y = genMerge.mkOption {
              type = T.nullOr T.int;
              default = null;
            };
          };
          c = {
            inherits = [ "b" ];
            options.z = genMerge.mkOption {
              type = T.listOf T.str;
              default = [ ];
            };
          };
        };
      }
    ]).config.schema;
in
{
  flake.tests.kind-mark-constant-tags.test-chain-marks-unmoved = {
    expr = map (k: schema.${k}.__mint.minted) [
      "a"
      "b"
      "c"
    ];
    expected = [
      "schemakind:8d96a587a9c2e8390db667f7f00a1c13443192019313534ea48317f309873d83"
      "schemakind:26b4aa6920840172870bc2b0b547c352b31f207fde0c5bdac4522bcf272132f9"
      "schemakind:06f8332b968f37f049f1d29c86444de9f6bd69d6f05924d19b878464ecec2a1f"
    ];
  };
}
