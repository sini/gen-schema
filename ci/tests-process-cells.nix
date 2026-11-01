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
        # a second label for component mints, which the runner counts apart from the kind mints
        else if tag == "component" then
          l: f: builtins.trace "${label}-component" (identity.hashIdentity tag l f)
        else
          identity.hashIdentity tag;
    };
  };

  # den-hoag-a7c9r U1 · `n` parentless kinds of four `str` options and no collection: every inert
  # component that is `null` or `[ ]` enters by one tag minted once per evaluation, so the component
  # mints are one per kind (its option types) plus the two constants.
  componentKinds =
    n:
    let
      s =
        (merge.evalModuleTree { } [
          { options.schema = S.mkSchemaOption { }; }
          {
            config.schema = builtins.listToAttrs (
              builtins.genList (i: {
                name = "k${toString i}";
                value.options = builtins.listToAttrs (
                  map
                    (o: {
                      name = o;
                      value = merge.mkOption { type = merge.types.str; };
                    })
                    [
                      "a"
                      "b"
                      "c"
                      "d"
                    ]
                );
              }) n
            );
          }
        ]).config.schema;
    in
    builtins.foldl' (a: k: builtins.seq s.${k}.__mint.minted (a + 1)) 0 (
      builtins.genList (i: "k${toString i}") n
    );
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
  # den-hoag-f1iza G1 · ONE HOST of the deepest kind of a `k`-deep chain (k_i inherits k_{i-1}, four `str`
  # options each): an instance in gen's engine, every option value and its `id_hash` read (an identity read,
  # which demands the kind's mark and so every ancestor's). The value is the count of options served their
  # definition, `4 k`; the runner reads the cost as the process's thunks.
  depthHost =
    k:
    let
      ks = builtins.genList (i: "k${toString (i + 1)}") k;
      optsOf =
        kn:
        builtins.listToAttrs (
          builtins.genList (o: {
            name = "${kn}o${toString (o + 1)}";
            value = merge.mkOption { type = merge.types.str; };
          }) 4
        );
      sch =
        (merge.evalModuleTree { } [
          { options.schema = S.mkSchemaOption { }; }
          (
            { config, ... }:
            {
              config.schema = builtins.listToAttrs (
                builtins.genList (i: {
                  name = "k${toString (i + 1)}";
                  value = {
                    options = optsOf "k${toString (i + 1)}";
                  }
                  // (if i > 0 then { inherits = [ config.schema."k${toString i}" ]; } else { });
                }) k
              );
            }
          )
        ]).config.schema;
      allOpts = builtins.concatMap (kn: builtins.attrNames (optsOf kn)) ks;
      h =
        (merge.evalModuleTree { } [
          { options.h = merge.mkOption { type = S.mkInstanceType { } sch."k${toString k}"; }; }
          {
            config.h = builtins.listToAttrs (
              map (o: {
                name = o;
                value = "${o}-v";
              }) allOpts
            );
          }
        ]).config.h;
    in
    builtins.seq h.id_hash (builtins.length (builtins.filter (o: h.${o} == "${o}-v") allOpts));
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
  component-mints-one-kind = componentKinds 1;
  component-mints-four-kinds = componentKinds 4;
  # den-hoag-a7c9r V1-a C2 · two constructions of one `mkType`-arm declaration (two schema evaluations),
  # each construction's mark read, then both imported into gen's engine: they meet at the declaration's
  # node, `decide` tells them apart, and gen-merge reads each record's key and mark to refuse the second
  # by name. Each construction's mark is minted once, whether `__mint` or the record reads it. (One
  # construction reached twice, a diamond, is decided by its seals and reads no key or mark, so it
  # cannot show a second mint.)
  mktype-two-constructions-mints =
    let
      # one declaration (one literal, so one declaration node) under two schema evaluations
      decl = {
        options.trail = merge.mkOption { type = merge.types.listOf merge.types.str; };
        config.trail = [ "k" ];
      };
      kindOf =
        (merge.evalModuleTree { } [
          {
            options.schema = S.mkSchemaOption {
              mkType =
                { defs, ... }:
                {
                  __functor =
                    _:
                    { ... }:
                    {
                      imports = map (d: d.value) defs;
                    };
                };
            };
          }
          { config.schema.k = decl; }
        ]).config.schema.k;
      a = kindOf;
      b =
        (merge.evalModuleTree { } [
          {
            options.schema = S.mkSchemaOption {
              mkType =
                { defs, ... }:
                {
                  __functor =
                    _:
                    { ... }:
                    {
                      imports = map (d: d.value) defs;
                    };
                };
            };
          }
          { config.schema.k = decl; }
        ]).config.schema.k;
      r = builtins.tryEval (
        builtins.deepSeq
          (merge.evalModuleTree { } [
            a
            b
          ]).config.trail
          true
      );
    in
    builtins.deepSeq [ a.__mint.minted b.__mint.minted ] (
      if r.success then
        throw "mktype-two-constructions-mints: the two constructions were not refused"
      else
        2
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
  # den-hoag-ux9xg · THE GUARD: a collection NOT declared `identity = false` holding a value that reads
  # its own instance's `id_hash` (the selfId class, an ADR-0025 item 1 enumerated exception, 9zyp7 OQ4):
  # the identity read has no solution and aborts uncatchably on every evaluator; the abort names the
  # kind, the collection and the declaration that takes it out of the identity. (A collection reading
  # only the instance's other fields is served: den-hoag-9zyp7 arm C and OQ2.)
  collection-identity-guard =
    (merge.evalModuleTree { } [
      (
        { config, ... }:
        {
          options.schema = S.mkSchemaOption {
            collections.excludes = {
              default = [ ];
              merge = acc: val: acc ++ val;
            };
          };
          options.hosts = S.mkInstanceRegistry { } config.schema.host;
          options.aspects = merge.mkOption { type = merge.types.attrsOf merge.types.anything; };
          config.schema.host = {
            options.addr = merge.mkOption { type = merge.types.str; };
            excludes = [ config.aspects.unwanted ];
          };
          config.hosts.igloo.addr = "10.0.1.1";
          config.aspects.unwanted.domain = config.hosts.igloo.id_hash;
        }
      )
    ]).config.hosts.igloo.id_hash;
  # den-hoag-ux9xg C1 · a computed field on a schema that declares a collection `identity = false` is
  # minted over the declaration with that collection taken out; a `computed` partial there aborts, and
  # the abort names the kind and the computed field.
  computed-projection-attribution =
    (merge.evalModuleTree { } [
      {
        options.schema = S.mkSchemaOption {
          collections.tags = {
            default = [ ];
            identity = false;
          };
          computed = c: _: { firstTag = builtins.head c.tags; };
        };
        config.schema.host.tags = [ "x" ];
      }
    ]).config.schema.host.__mint.minted;
  # den-hoag-ux9xg C1 · the same partial `computed`, met through an INSTANCE read: the stamp's path
  # forces the sealed subject, and the abort still names the kind and the computed field.
  computed-projection-instance =
    (merge.evalModuleTree { } [
      (
        { config, ... }:
        {
          options.schema = S.mkSchemaOption {
            collections.tags = {
              default = [ ];
              identity = false;
            };
            computed = c: _: { firstTag = builtins.head c.tags; };
          };
          options.hosts = S.mkInstanceRegistry { } config.schema.host;
          config.schema.host = {
            options.addr = merge.mkOption { type = merge.types.str; };
            tags = [ "x" ];
          };
          config.hosts.igloo.addr = "10.0.1.1";
        }
      )
    ]).config.hosts.igloo.id_hash;
  # den-hoag-9zyp7 OQ2 · THE RESIDUE, pinned at its class: a kind whose identity-bearing collection
  # reads an instance of itself composes (gen-demo), but where the kind also inherits ANOTHER tree's
  # kind of the same name, the two meet by name (`__keyEq.meeting`), the meeting forces the mark, and
  # the read recurses uncatchably, as before the meeting. An open ADR-0039 rule (1) defect; a move
  # off the abort is the defect closing, and this cell then moves with it. Its control, the other
  # kind renamed, is `schema-inheritance`'s `test-an-instance-read-composes-beside-another-trees-kind`.
  inheriting-same-name-residue =
    let
      excludes = {
        default = [ ];
        merge = acc: val: acc ++ val;
      };
      otherHost =
        (merge.evalModuleTree { } [
          (
            { config, ... }:
            {
              options.schema = S.mkSchemaOption { collections.excludes = excludes; };
              config.schema.conf = { };
              config.schema.host = {
                inherits = [ config.schema.conf ];
                options.addr = merge.mkOption { type = merge.types.str; };
              };
            }
          )
        ]).config.schema.host;
    in
    (merge.evalModuleTree { } [
      (
        { config, ... }:
        {
          options.schema = S.mkSchemaOption { collections.excludes = excludes; };
          options.hosts = S.mkInstanceRegistry { } config.schema.host;
          options.aspects = merge.mkOption { type = merge.types.attrsOf merge.types.anything; };
          config.schema.conf = { };
          config.schema.host = {
            inherits = [
              config.schema.conf
              otherHost
            ];
            options.addr = merge.mkOption { type = merge.types.str; };
            excludes = [ config.aspects.unwanted ];
          };
          config.hosts.igloo.addr = "10.0.1.1";
          config.aspects.unwanted.domain = config.hosts.igloo.addr;
        }
      )
    ]).config.hosts.igloo.addr;
  # den-hoag-ux9xg C1 · THE GUARD with a collection whose name sorts after every built-in (`zones`
  # after `validators`): the attribution does not depend on where the collection's tag sorts.
  collection-identity-guard-sorted-last =
    (merge.evalModuleTree { } [
      (
        { config, ... }:
        {
          options.schema = S.mkSchemaOption {
            collections.zones = {
              default = [ ];
              merge = acc: val: acc ++ val;
            };
          };
          options.hosts = S.mkInstanceRegistry { } config.schema.host;
          options.aspects = merge.mkOption { type = merge.types.attrsOf merge.types.anything; };
          config.schema.host = {
            options.addr = merge.mkOption { type = merge.types.str; };
            zones = [ config.aspects.unwanted ];
          };
          config.hosts.igloo.addr = "10.0.1.1";
          config.aspects.unwanted.domain = config.hosts.igloo.id_hash;
        }
      )
    ]).config.hosts.igloo.id_hash;
  depth-host-16 = depthHost 16;
  depth-host-32 = depthHost 32;
  depth-host-64 = depthHost 64;
  # A predicate ill-typed over its base aborts uncatchably; the abort names the refinement.
  refined-attribution = outsideRead (S.refined T.str {
    check = v: v > 0;
    message = "must be positive";
  }) "a";
}
.${arm}
