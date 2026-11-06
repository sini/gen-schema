# THE AGREEMENT RAZOR (den-hoag-ien5k T3, spec `specs/2026-11-01-ien5k-t3-syntactic-membership-spec.md` §3a GS1).
# `declaredField regOpt "aspects"` answers a node's membership from its declarations, or `null`; the module-system
# read is `config.spindles.<node>.aspects`. Over a fleet of 4 nodes with one plant (at the last node, or on the
# kind, the registry or the schema; `ci/test-fixtures/declared-field-fleet.nix`), a cell is GREEN iff every node's
# answer is `null` or equals the module read (refusals included), AND the number of nodes that fall back is the
# shape's own: on this fixture a reader serving two survivors' fold can agree by coincidence of order, so the
# count is what sees the survivor count there (`kindcfg`, `samedefault`).
#   served         none, force, apply, omit, view, enum (s3 refuses on both sides), kinddefault, kindforce,
#                  kinddefaultnodeforce
#   falls back 1   twodefs, undeclared, structured, structextra, samedefault, nodemkif
#   falls back 4   kindcfg, kindmkif, parent, extramod, derive, a function module, a validator, a refinement of
#                  the field, a ref binding module, a `mkType` kind, a mixin, and the registry option declared
#                  twice (`redecl`: a second declaration's type carries a module defining the field)
# Red at gen-schema main 1d5d117: `declaredField` is absent, so every cell aborts on the missing attribute.
{ genMerge, genSchema, ... }:
let
  fleet =
    plant:
    removeAttrs (import ../test-fixtures/declared-field-fleet.nix { inherit genMerge genSchema plant; })
      [
        "rows"
      ];
  expect = fellBack: {
    inherit fellBack;
    disagree = [ ];
  };
  shapes = {
    none = 0;
    force = 0;
    apply = 0;
    omit = 0;
    view = 0;
    enum = 0;
    kinddefault = 0;
    kindforce = 0;
    kinddefaultnodeforce = 0;
    twodefs = 1;
    undeclared = 1;
    structured = 1;
    structextra = 1;
    samedefault = 1;
    nodemkif = 1;
    kindcfg = 4;
    kindmkif = 4;
    parent = 4;
    extramod = 4;
    derive = 4;
    funmodule = 4;
    validator = 4;
    refinement = 4;
    reffield = 4;
    mktype = 4;
    mixin = 4;
    redecl = 4;
  };
in
{
  flake.tests.declared-field =
    builtins.listToAttrs (
      map (p: {
        name = "test-razor-${p}";
        value = {
          expr = fleet (if p == "none" then null else p);
          expected = expect shapes.${p};
        };
      }) (builtins.attrNames shapes)
    )
    // {
      # the published datum on the kind value and on the registry record, read off the built fleet
      test-the-kind-states-its-own-definitions-as-written =
        let
          inherit (genMerge) mkDefault mkOption types;
          k =
            (genSchema.evalSchema { } [
              {
                config.schema.spindle = {
                  options.aspects = mkOption { type = types.listOf types.str; };
                  config.aspects = mkDefault [ "spare" ];
                };
              }
            ]).spindle;
        in
        {
          expr = map (d: d.value) k._instanceDefinitions.aspects;
          expected = [ (mkDefault [ "spare" ]) ];
        };
    };
}
