# den-hoag-registry-types-outside-kind-d24lq: a deferred `declarationOf "<kind>"` resolves only through
# a registry binding, so a value merged where nothing binds it is refused rather than admitted raw.
# The in-kind rows are the controls: a refuse-everything implementation reds them.
{
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema)
    evalSchema
    mkInstanceRegistry
    mkInstanceType
    declarationOf
    setOf
    ;
  t = genMerge.types;
  verdict =
    v:
    let
      r = builtins.tryEval (builtins.deepSeq v v);
    in
    if r.success then r.value else "REFUSED";
  outside =
    type: v:
    verdict
      (genMerge.evalModuleTree { } [
        { options.o = genMerge.mkOption { inherit type; }; }
        { o = v; }
      ]).config.o;
  schema = evalSchema {
    modules = [
      {
        config.schema.host.options.addr = genMerge.mkOption {
          type = t.str;
          default = "x";
        };
        config.schema.svc.options.host = genMerge.mkOption { type = declarationOf "host"; };
        config.schema.grp.options.members = genMerge.mkOption {
          type = setOf (declarationOf "host");
          default = [ ];
        };
      }
    ];
  };
  inKind =
    host: members:
    (genMerge.evalModuleTree { } [
      (
        { config, ... }:
        {
          options.hosts = mkInstanceRegistry schema.host { };
          options.svcs = mkInstanceRegistry schema.svc { refs.host = config.hosts; };
          options.grps = mkInstanceRegistry schema.grp { refs.members = config.hosts; };
          config.hosts.a = { };
          config.hosts.b = { };
          config.svcs.s.host = host;
          config.grps.g.members = members;
        }
      )
    ]).config;
in
{
  flake.tests.ref-unbound = {
    test-unbound-outside-a-kind-refused = {
      expr = {
        dangling = outside (declarationOf "host") "nope";
        wellNamed = outside (declarationOf "host") "a";
        nullOr = outside (t.nullOr (declarationOf "host")) "nope";
        listOf = outside (t.listOf (declarationOf "host")) [ "nope" ];
        setOfDuplicates = outside (setOf (declarationOf "host")) [
          "a"
          "a"
        ];
        nullOrNull = outside (t.nullOr (declarationOf "host")) null;
        setOfEmpty = outside (setOf (declarationOf "host")) [ ];
      };
      expected = {
        dangling = "REFUSED";
        wellNamed = "REFUSED";
        nullOr = "REFUSED";
        listOf = "REFUSED";
        setOfDuplicates = "REFUSED";
        nullOrNull = null;
        setOfEmpty = [ ];
      };
    };
    test-kind-without-registry-refused = {
      expr =
        verdict
          (genMerge.evalModuleTree { } [
            {
              options.one = genMerge.mkOption { type = mkInstanceType schema.svc { }; };
              config.one.host = "a";
            }
          ]).config.one.host;
      expected = "REFUSED";
    };
    test-bound-in-a-kind-resolves = {
      expr = {
        host = verdict (inKind "a" [ ]).svcs.s.host.name;
        members = verdict (
          map (h: h.name)
            (inKind "a" [
              "a"
              "a"
              "b"
            ]).grps.g.members
        );
        dangling = verdict (inKind "nope" [ ]).svcs.s.host.name;
      };
      expected = {
        host = "a";
        members = [
          "a"
          "b"
        ];
        dangling = "REFUSED";
      };
    };
    # The binding rebuilds a refined layer over a bound base, so a refinement over a deferred ref is
    # served in a kind and still enforced there; outside a kind it refuses as its leaf does.
    test-refined-bound-in-a-kind-resolves =
      let
        notB = {
          check = v: v != "b";
          message = "not b";
        };
        small = {
          check = v: builtins.length v < 3;
          message = "fewer than 3";
        };
        rschema = evalSchema {
          modules = [
            {
              config.schema.host = { };
              config.schema.r.options = {
                h = genMerge.mkOption { type = genSchema.refined (declarationOf "host") notB; };
                n = genMerge.mkOption {
                  type = t.nullOr (genSchema.refined (declarationOf "host") notB);
                  default = null;
                };
                l = genMerge.mkOption {
                  type = genSchema.refined (t.listOf (declarationOf "host")) small;
                  default = [ ];
                };
              };
            }
          ];
        };
        run =
          r:
          (genMerge.evalModuleTree { } [
            (
              { config, ... }:
              {
                options.hosts = mkInstanceRegistry rschema.host { };
                options.rs = mkInstanceRegistry rschema.r {
                  refs.h = config.hosts;
                  refs.n = config.hosts;
                  refs.l = config.hosts;
                };
                config.hosts.a = { };
                config.hosts.b = { };
                config.rs.y = r;
              }
            )
          ]).config.rs.y;
      in
      {
        expr = {
          scalar = verdict (run { h = "a"; }).h.name;
          nullOr =
            verdict
              (run {
                h = "a";
                n = "a";
              }).n.name;
          listOf = verdict (
            map (h: h.name)
              (run {
                h = "a";
                l = [
                  "a"
                  "b"
                ];
              }).l
          );
          refinementFails = verdict (run { h = "b"; }).h.name;
          listRefinementFails = verdict (
            map (h: h.name)
              (run {
                h = "a";
                l = [
                  "a"
                  "b"
                  "a"
                ];
              }).l
          );
          outside = outside (genSchema.refined (declarationOf "host") notB) "a";
        };
        expected = {
          scalar = "a";
          nullOr = "a";
          listOf = [
            "a"
            "b"
          ];
          refinementFails = "REFUSED";
          listRefinementFails = "REFUSED";
          outside = "REFUSED";
        };
      };
    # The relation itself, read off the functor: gen-merge's declaration path refuses two kinds by
    # name before binOp is reached, so only a direct call discriminates binOp's own refusal and its
    # bound-wins join.
    test-relation-joins-bound-and-refuses-two-kinds =
      let
        f = k: (declarationOf k).functor;
        join =
          a: b:
          let
            r = (f "host").binOp a b;
          in
          if r == null then "REFUSED" else r.bound or "no-flag";
        u = (f "host").payload;
        b = u // {
          bound = true;
        };
      in
      {
        expr = {
          unboundUnbound = join u u;
          unboundBound = join u b;
          boundUnbound = join b u;
          twoKinds = join u (f "user").payload;
        };
        expected = {
          unboundUnbound = false;
          unboundBound = true;
          boundUnbound = true;
          twoKinds = "REFUSED";
        };
      };
    test-direct-registry-unaffected = {
      expr =
        let
          reg.a = {
            name = "a";
            id_hash = "h-a";
            _identityKeys = [ "name" ];
          };
        in
        {
          good = verdict (outside (declarationOf reg) "a").name;
          dangling = outside (declarationOf reg) "nope";
        };
      expected = {
        good = "a";
        dangling = "REFUSED";
      };
    };
  };
}
