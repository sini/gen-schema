# The constant component tags (den-hoag-a7c9r U1): gen-algebra mints the `null` and `[ ]` tags once per
# partial application and this library shares one partial, so every kind's absent function, empty
# collection and `null` default enter its mark by one shared tag. Byte identity is the claim: the marks
# of a three-kind chain, read before the sharing, pinned verbatim.
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
      "schemakind:36964aa4169628a419c6733aad6783c4c7c7a72c7fd70bb7bd97062f61269356"
      "schemakind:e8eb5b83649c39542942e73aba8b74b115f2ad06bd2d0276a79ea2ce90bf4f89"
    ];
  };
}
