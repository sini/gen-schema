# A kind's mixins over each shape of `baseModule`, and on the `mkType` arm: carried, or refused by name,
# never dropped (den-hoag-8kdu2). The fixture kind `user` holds `lst = [ "own" ]`; the mixin reads
# nothing off the base and contributes `lst = [ "mx" ]` and an option `mxo`. Five readers, which must
# agree: `pub` the published collection, `seen` a `computed` hook, `opt` `mxo` among `options`, `inst`
# `config.mxo` of an instance in gen's engine, `mark` the provenance mark.
#
# RED before: a `null`, function-module or path base, and the `mkType` arm, ran no mixin pipeline, so
# every reader agreed on `[ "own" ]` and no `mxo`: the mixin was dropped silently. The refusal texts
# are pinned in `../tests-error.nix` (`mixin-base-refusals`).
{
  genSchema,
  genMerge,
  ...
}:
let
  gm = genMerge;
  str =
    d:
    gm.mkOption {
      type = gm.types.str;
      default = d;
    };
  try =
    v:
    let
      r = builtins.tryEval (builtins.deepSeq v v);
    in
    if r.success then r.value else "REFUSED";

  mixPlain = genSchema.mkMixin { } (_: {
    lst = [ "mx" ];
    mxo = str "m";
  });
  mixReq = genSchema.mkMixin { requires = [ "port" ]; } (_: {
    lst = [ "mx" ];
    mxo = str "m";
  });
  # a caller `mkType` that imports its defs and the `kindModule` it is handed
  mkTypeImportsBase =
    { defs, kindModule, ... }:
    {
      __functor =
        _:
        { ... }:
        {
          imports = map (d: d.value) defs ++ (if kindModule == null then [ ] else [ kindModule ]);
        };
    };
  kindOf =
    {
      baseModule ? null,
      mixins ? [ ],
      mkType ? null,
      twin ? false,
    }:
    (gm.evalModuleTree { } (
      [
        {
          options.schema = genSchema.mkSchemaOption {
            collections.lst.default = [ ];
            computed = colls: _: { seen = colls.lst; };
            inherit baseModule mixins mkType;
          };
        }
        {
          config.schema.user = {
            options.ua = str "u";
            lst = [ "own" ];
          };
        }
      ]
      # the twin: the kind writes the mixin's contribution itself
      ++ (
        if twin then
          [
            {
              config.schema.user = {
                lst = [ "mx" ];
                options.mxo = str "m";
              };
            }
          ]
        else
          [ ]
      )
    )).config.schema.user;
  read = k: {
    pub = try (k.lst or "NOPUB");
    seen = try k.seen;
    opt = try (builtins.elem "mxo" (builtins.attrNames k.options));
    inst = try (
      (gm.evalModuleTree { } [
        k
        { config.ua = "u"; }
      ]).config.mxo or "ABSENT"
    );
    mark = try (builtins.isString k.__mint.minted);
  };
  carried = {
    pub = [
      "own"
      "mx"
    ];
    seen = [
      "own"
      "mx"
    ];
    opt = true;
    inst = "m";
    mark = true;
  };
  refused = {
    pub = "REFUSED";
    seen = "REFUSED";
    opt = "REFUSED";
    inst = "REFUSED";
    mark = "REFUSED";
  };
in
{
  # G1: an absent base is the empty record, so the mixin is carried, equal to the twin
  flake.tests.kind-mixin-base-shapes.test-null-base-carries-the-mixin = {
    expr = read (kindOf {
      mixins = [ mixPlain ];
    });
    expected = carried;
  };
  # G2: over the empty record a mixin whose `requires` the base cannot meet is refused, as over `{ }`
  flake.tests.kind-mixin-base-shapes.test-null-base-refuses-an-unmet-requires = {
    expr = read (kindOf {
      mixins = [ mixReq ];
    });
    expected = refused;
  };
  # G3: a base the record algebra cannot read is refused on every reader
  flake.tests.kind-mixin-base-shapes.test-function-module-base-is-refused-on-every-reader = {
    expr = read (kindOf {
      baseModule = _: ({ ... }: { });
      mixins = [ mixPlain ];
    });
    expected = refused;
  };
  flake.tests.kind-mixin-base-shapes.test-path-base-is-refused-on-every-reader = {
    expr = read (kindOf {
      baseModule = ../test-fixtures/empty-module.nix;
      mixins = [ mixPlain ];
    });
    expected = refused;
  };
  # G9 (OQ-1 arm R): mixins on the `mkType` arm are refused at its WHNF, on every reader, with and
  # without a base; the twin on that arm is served
  flake.tests.kind-mixin-base-shapes.test-mktype-arm-refuses-mixins-over-an-attrset-base = {
    expr = read (kindOf {
      baseModule = { };
      mixins = [ mixPlain ];
      mkType = mkTypeImportsBase;
    });
    expected = refused;
  };
  flake.tests.kind-mixin-base-shapes.test-mktype-arm-refuses-mixins-over-a-null-base = {
    expr = read (kindOf {
      mixins = [ mixPlain ];
      mkType = mkTypeImportsBase;
    });
    expected = refused;
  };
  flake.tests.kind-mixin-base-shapes.test-mktype-arm-refusal-is-at-the-kind-whnf = {
    expr =
      (builtins.tryEval
        (kindOf {
          mixins = [ mixPlain ];
          mkType = mkTypeImportsBase;
        }).kind
      ).success;
    expected = false;
  };
  # G4 controls: the `{ }` and `kind -> { }` bases carry, the twin is served, and the twin on the
  # `mkType` arm is served (the refusal is the mixin's, not the arm's)
  flake.tests.kind-mixin-base-shapes.test-control-empty-base-carries = {
    expr = read (kindOf {
      baseModule = { };
      mixins = [ mixPlain ];
    });
    expected = carried;
  };
  flake.tests.kind-mixin-base-shapes.test-control-kind-function-to-attrset-base-carries = {
    expr = read (kindOf {
      baseModule = _: { };
      mixins = [ mixPlain ];
    });
    expected = carried;
  };
  flake.tests.kind-mixin-base-shapes.test-control-twin = {
    expr = read (kindOf {
      twin = true;
    });
    expected = carried;
  };
  flake.tests.kind-mixin-base-shapes.test-control-empty-base-refuses-an-unmet-requires = {
    expr = read (kindOf {
      baseModule = { };
      mixins = [ mixReq ];
    });
    expected = refused;
  };
  flake.tests.kind-mixin-base-shapes.test-control-mktype-twin-is-served = {
    expr = read (kindOf {
      twin = true;
      mkType = mkTypeImportsBase;
    });
    expected = carried // {
      pub = "NOPUB";
    };
  };
  flake.tests.kind-mixin-base-shapes.test-control-function-module-base-without-mixins-is-served = {
    expr =
      (read (kindOf {
        baseModule = _: ({ ... }: { });
      })).pub;
    expected = [ "own" ];
  };
  flake.tests.kind-mixin-base-shapes.test-control-path-base-without-mixins-is-served = {
    expr = read (kindOf {
      baseModule = ../test-fixtures/empty-module.nix;
    });
    expected = {
      pub = [ "own" ];
      seen = [ "own" ];
      opt = false;
      inst = "ABSENT";
      mark = true;
    };
  };
}
