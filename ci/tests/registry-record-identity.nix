# THE REGISTRY RECORD'S DERIVED FIELD IS NOT MINTED (den-hoag-ien5k T3, arm (B) of the identity ruling, ADR-0034).
# `mkInstanceRegistry` writes `_instanceDefinitions` on its option record as a function of the record's own `type`,
# which the kind mark already mints, so the plane mints no path for its name: a kind declaring a registry keeps its
# mark (`instance-embedding-identity`, `instance-type-identity` a8, at their pinned digests). The controls here: a
# user-visible change to the same registry option still moves the declaring kind's mark, by its type and by an
# attribute name a declaration writes. A declaration writing `_instanceDefinitions` itself is refused by name
# (`ci/tests-error.nix`, `registry-record-identity`), so the exclusion hides no content.
{ genSchema, genMerge, ... }:
let
  inherit (genMerge) mkOption types;
  inherit (genSchema) evalSchema mkInstanceRegistry;
  inner = evalSchema { } [
    {
      config.schema.user.options.uname = mkOption { type = types.str; };
      config.schema.guest.options.gname = mkOption { type = types.str; };
    }
  ];
  markOf =
    users:
    (evalSchema { } [
      {
        config.schema.site = {
          options.addr = mkOption { type = types.str; };
          options.users = users;
        };
      }
    ]).site.__mint.minted;
  base = markOf (mkInstanceRegistry { } inner.user);
in
{
  flake.tests.registry-record-identity = {
    test-the-same-registry-declaration-mints-one-mark = {
      expr = markOf (mkInstanceRegistry { } inner.user) == base;
      expected = true;
    };
    test-a-changed-registry-type-moves-the-mark = {
      expr = markOf (mkInstanceRegistry { } inner.guest) == base;
      expected = false;
    };
    test-a-declared-attribute-on-the-registry-record-moves-the-mark = {
      expr = markOf (mkInstanceRegistry { } inner.user // { example = 1; }) == base;
      expected = false;
    };
  };
}
