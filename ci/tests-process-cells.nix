# THE PER-PROCESS CELLS — fixtures whose verdict is a COUNT on stderr, one fixture per process.
#
# WHY THESE CANNOT BE SUITE CELLS. The subject is how many times the kind mark is MINTED, and a mint
# recomputed per instance returns the same string as one minted once: no value a suite cell can read
# tells them apart. The runner in `tests-process.nix` counts a spy's trace lines instead.
#
# THE SPY: gen-schema over an `identity` whose `hashIdentity` traces `label` on every kind mint (tag
# `schemakind`), so the label's count on stderr is the number of kind marks the evaluation minted.
#
# Wiring: each dependency through its own entry with explicit arguments, the way each flake's own
# `lib` output builds it. One prelude, identity and graph (the ci flake's root nodes) serve every
# library; the count does not depend on which revision of them is read.
{
  arm,
  libSrc,
  preludeSrc,
  identitySrc,
  graphSrc,
  algebraSrc,
  typesSrc,
  memoSrc,
  scopeSrc,
  mergeSrc,
  # A trace label generated fresh per run by the runner, which counts its lines on stderr.
  label,
}:
let
  prelude = import preludeSrc { };
  identity = import "${identitySrc}/lib";
  graph = import graphSrc { inherit prelude; };
  merge = import mergeSrc {
    inherit prelude;
    types = import typesSrc {
      inherit prelude identity;
      algebra = import "${algebraSrc}/lib";
    };
    memo = import memoSrc { inherit prelude graph; };
    scope = import scopeSrc {
      inherit prelude graph identity;
      algebra = import "${algebraSrc}/lib";
    };
  };
  S = import libSrc {
    inherit prelude merge graph;
    algebra = import "${algebraSrc}/lib";
    identity = identity // {
      hashIdentity =
        tag:
        if tag == "schemakind" then
          l: f: builtins.trace label (identity.hashIdentity tag l f)
        else
          identity.hashIdentity tag;
    };
  };

  intOpt = merge.mkOption {
    type = merge.types.int;
    default = 1;
  };
  treeOf =
    i:
    (merge.evalModuleTree { } [
      { options.schema = S.mkSchemaOption { }; }
      {
        config.schema.base.options.b = intOpt;
        config.schema.sub = {
          inherits = [ "base" ];
          options."s${toString i}" = intOpt;
        };
      }
    ]).config.schema;
  # `n` instances of one kind with a parent: each instance applies the kind's `__functor`, whose
  # module key reads the kind's mark.
  instances =
    n:
    let
      t = treeOf 0;
      reg =
        (merge.evalModuleTree { } [
          { options.hosts = S.mkInstanceRegistry { } t.sub; }
          {
            config.hosts = builtins.listToAttrs (
              builtins.genList (i: {
                name = "h${toString i}";
                value = { };
              }) n
            );
          }
        ]).config.hosts;
    in
    builtins.deepSeq (builtins.seq t.sub.__mint.minted (builtins.mapAttrs (_: h: h.b + h.s0) reg)) n;
  # A refined type's predicate applications (den-hoag-refined-outside-kind-silent-1jlsq): the spy
  # refinement traces `label` once per application, so the label's count is the cost.
  T = merge.types;
  spyPos = {
    check = v: builtins.trace label (v > 0);
    message = "must be positive";
  };
  inKindRead =
    ty:
    (merge.evalModuleTree { } [
      { options.schema = S.mkSchemaOption { }; }
      (
        { config, ... }:
        {
          config.schema.widget.options.n = merge.mkOption { type = ty; };
          options.widgets = S.mkInstanceRegistry { } config.schema.widget;
        }
      )
      { config.widgets.w1.n = 5; }
    ]).config.widgets.w1.n;
  outsideRead =
    ty: v:
    (merge.evalModuleTree { } [
      { options.o = merge.mkOption { type = ty; }; }
      { config.o = v; }
    ]).config.o;
in
{
  # ONE kind, one instance and eight: the kind marks minted must not move with the instance count.
  mints-one-instance = instances 1;
  mints-eight-instances = instances 8;
  # THE SPY'S LIVE CONTROL: eight independent trees mint eight `sub`s (and their `base`s), so a spy
  # that counts each mint reads at least eight here.
  mints-eight-kinds = builtins.foldl' (a: i: builtins.seq (treeOf i).sub.__mint.minted (a + 1)) 0 (
    builtins.genList (i: i) 8
  );
  # One application per demanded value: the type decides its own refinements, and the kind pass
  # does not re-check them.
  refined-cost-in-kind = inKindRead (S.refined T.int spyPos);
  refined-cost-in-kind-lazy = inKindRead (S.refined T.int (spyPos // { lazy = true; }));
  refined-cost-outside = outsideRead (S.refined T.int spyPos) 5;
  refined-cost-outside-list = outsideRead (T.listOf (S.refined T.int spyPos)) [
    1
    2
    3
  ];
  # A predicate ill-typed over its base aborts uncatchably; the abort names the refinement.
  refined-attribution = outsideRead (S.refined T.str {
    check = v: v > 0;
    message = "must be positive";
  }) "a";
}
.${arm}
