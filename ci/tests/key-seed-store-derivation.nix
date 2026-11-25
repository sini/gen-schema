# A kept collection whose seed and value are store-path derivations (nixpkgs `lib.toDerivation`, whose `outPath` is
# `builtins.storePath`), under pure evaluation, where `storePath` is refused uncatchably: the kind key reads the value
# without forcing `outPath`, at the top and nested in a list and a record (den-hoag-1gb0t). The seed and the value are
# two DISTINCT `toDerivation` values: Lix's `==` short-circuits on one shared binding and would not force it. Each row
# reads one declaration position under two schema evaluations: one node, and the key equal exactly where the mark is.
{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  T = genMerge.types;
  # never realised: pure evaluation refuses `storePath` on any string, so the path need not exist
  p1 = "/nix/store/00000000000000000000000000000000-seed-a";
  p2 = "/nix/store/11111111111111111111111111111111-seed-b";
  kindUnder =
    seed: value:
    (genMerge.evalModuleTree { } [
      {
        options.schema = genSchema.mkSchemaOption {
          collections.tags = {
            merge = _: v: v;
            default = seed;
          };
        };
      }
      {
        config.schema.k = {
          options.trail = genMerge.mkOption { type = T.str; };
          tags = value;
        };
      }
    ]).config.schema.k;
  # forced whole and never caught, so a refusal reds the cell
  keyOf =
    k:
    let
      key = (k.__functor k { }).key;
    in
    builtins.deepSeq key key;
  read = a: b: {
    keyed = builtins.isString (keyOf a) && builtins.isString (keyOf b);
    w = a.__kindWitness == b.__kindWitness;
    agree = (a.__mint.minted == b.__mint.minted) == (keyOf a == keyOf b);
  };
  holds = {
    keyed = true;
    w = true;
    agree = true;
  };
  # `wrap` places the derivation: at the top, in a list, in a record
  rowsOf = wrap: {
    samePath = read (kindUnder (wrap (lib.toDerivation p1)) (wrap (lib.toDerivation p1))) (
      kindUnder (wrap (lib.toDerivation p1)) (wrap (lib.toDerivation p1))
    );
    twoPaths = read (kindUnder (wrap (lib.toDerivation p1)) (wrap (lib.toDerivation p1))) (
      kindUnder (wrap (lib.toDerivation p1)) (wrap (lib.toDerivation p2))
    );
  };
in
{
  flake.tests.key-seed-store-derivation = {
    test-two-distinct-store-derivations-at-a-seed-key-under-pure-eval = {
      expr = rowsOf (d: d);
      expected = {
        samePath = holds;
        twoPaths = holds;
      };
    };
    test-a-store-derivation-in-a-list-or-a-record-at-a-seed-keys-under-pure-eval = {
      expr = {
        list = rowsOf (d: [ d ]);
        record = rowsOf (d: {
          p = d;
        });
      };
      expected = {
        list = {
          samePath = holds;
          twoPaths = holds;
        };
        record = {
          samePath = holds;
          twoPaths = holds;
        };
      };
    };
  };
}
