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
      "schemakind:c4e7c77da23e322efa37fa53f7fa058eb44788347e1853ec848a7de8c74d2ec8"
      "schemakind:7793b6622232711e3ff39fc62749501cb32a79f2c52c5c5ebde6b5f8f8ed5715"
      "schemakind:f8b854de59c36bf5892b316c688bb8dc668956193ef4611bf266ede289cfb0ce"
    ];
  };
}
