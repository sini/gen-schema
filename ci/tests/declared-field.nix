# THE AGREEMENT RAZOR (den-hoag-ien5k T3, spec `specs/2026-11-01-ien5k-t3-syntactic-membership-spec.md` §3a GS1).
# `declaredField regOpt "aspects"` answers a node's membership from its declarations, or `null`; the module-system
# read is `config.spindles.<node>.aspects`. Over a fleet of 4 nodes with one plant (at the last node, or on the
# kind, the registry or the schema; `ci/test-fixtures/declared-field-fleet.nix`), a cell is GREEN iff every node's
# answer is `null` or equals the module read (refusals included), AND the number of nodes that fall back is the
# shape's own: on this fixture a reader serving two survivors' fold can agree by coincidence of order, so the
# count is what sees the survivor count there (`kindcfg`, `samedefault`).
#   served         none, force, apply, omit, view, enum (s3 refuses on both sides), kinddefault, kindforce,
#                  kinddefaultnodeforce, and the declarations the record states (C7): an extra module declaring a
#                  key the node sets (`extradecl`), one redeclaring the field (`extraredecl`, its `apply` served), the
#                  node setting the instance's own `name` (`ownname`)
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
    extradecl = 0;
    extraredecl = 0;
    ownname = 0;
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
      # a field whose type carries a module set falls back to the module read (den-hoag-hil68: `evalOptionValue`
      # refuses a nested type outside an evaluation, so the reader never folds one), and never refuses the read
      test-a-nested-typed-field-falls-back-to-the-module-read =
        let
          inherit (genMerge) mkOption types;
          kind =
            (genSchema.evalSchema { } [
              {
                config.schema.loom.options.frames = mkOption {
                  type = types.attrsOf (types.submodule { options.w = mkOption { type = types.int; }; });
                  default = { };
                };
              }
            ]).loom;
          ev = genMerge.evalModuleTree { } [
            {
              options.looms = genSchema.mkInstanceRegistry { } kind;
              config.looms.l0.frames.f.w = 1;
              config.looms.l1 = { };
            }
          ];
          read = genSchema.declaredField ev.options.looms "frames";
        in
        {
          expr = {
            answers = map read [
              "l0"
              "l1"
            ];
            module = builtins.mapAttrs (_: l: l.frames) ev.config.looms;
          };
          expected = {
            answers = [
              null
              null
            ];
            module = {
              l0.f.w = 1;
              l1 = { };
            };
          };
        };
      # a `mkType` caller that states its datum, stamped (`_internal.stampInstanceDefinitions`), is served; the same
      # datum unstamped is not read (the razor's `mktype` shape states none and falls back 4/4)
      test-a-mktype-kind-stating-its-datum-is-served =
        let
          inherit (genMerge) mkOption types;
          mod = {
            options.aspects = mkOption {
              type = types.listOf types.str;
              default = [ ];
            };
          };
          kindWith =
            datum:
            (genMerge.evalModuleTree { } [
              {
                options.schema = genSchema.mkSchemaOption {
                  mkType =
                    { ... }:
                    {
                      __functor = _: _: mod;
                      _instanceDefinitions = datum;
                    };
                };
              }
              { config.schema.spindle = { }; }
            ]).config.schema.spindle;
          readWith =
            datum:
            let
              ev = genMerge.evalModuleTree { } [
                {
                  options.spindles = genSchema.mkInstanceRegistry { } (kindWith datum);
                  config.spindles.s0.aspects = [ "loom" ];
                }
              ];
            in
            genSchema.declaredField ev.options.spindles "aspects" "s0";
        in
        {
          expr = {
            stamped = readWith (genSchema._internal.stampInstanceDefinitions { });
            unstamped = readWith {
              by = null;
              fields = { };
            };
          };
          expected = {
            stamped = [ "loom" ];
            unstamped = null;
          };
        };
      # a record stating the datum's name without the library's token is not read: every node falls back
      test-a-forged-datum-is-not-read =
        let
          inherit (genMerge) mkOption types;
          kind =
            (genSchema.evalSchema { } [
              { config.schema.spindle.options.aspects = mkOption { type = types.listOf types.str; }; }
            ]).spindle;
          ev = genMerge.evalModuleTree { } [
            {
              options.spindles = genSchema.mkInstanceRegistry { } kind // {
                _instanceDefinitions = {
                  by.t = _: null;
                  fields.aspects = [
                    {
                      file = "forged";
                      value = [ "forged" ];
                    }
                  ];
                };
              };
              config.spindles.s0.aspects = [ "loom" ];
            }
          ];
        in
        {
          expr = genSchema.declaredField ev.options.spindles "aspects" "s0";
          expected = null;
        };
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
