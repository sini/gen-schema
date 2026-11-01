# THE LAYERED INTROSPECTION'S CASES (den-hoag-f1iza), one value per case, read by
# `ci/tests/kind-layered-introspection.nix` against the values the full evaluation publishes (the a7c9r
# bundle's head, before the layering). Each case is a shape the layering must publish unchanged, or a shape
# one of its predicate's conjuncts sends to the full evaluation:
#   shape-*   a 5-deep chain (k_i inherits k_{i-1}, four `str` options each): every kind's option leaves
#             (type name, declarations), refs and refinements names, and one instance's values in gen's
#             engine. `fn` (every kind's options in a function module), `mixed` (odd levels only),
#             `diamond` (k_i inherits k_{i-1} and k_{i-2}), `sealed` (k1 also declares a submodule
#             option), `libstr` (k1 also declares a nixpkgs `lib.types.str` option, a type with no mark)
#             and `redeclare` (every level declares k1's first option again, a leaf two sources declare).
#   fan-*     DISPATCH item 10's declaration-count hazard: `d` inheriting N = 2, 3, 4 kinds in every order,
#             over one shared ancestor or none: option names, `ancestorsForKind` order, gen's engine values.
#   honest    a7c9r v1 gate C1: an honest content edit of a parent value, refused at every composing door.
#   forged    a def whose `_file` carries the resolver's prefix and is not the resolver's value (CF1).
#   key       a parent and a child def naming one module `key`, which gen-merge's closure dedups (CF2).
#   methods   a parented kind with a `methods` collection, an injected module (the `injected` conjunct).
#   fnParent  a parent function module whose option's default reads the child's (the parents' flag).
{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  T = genMerge.types;
  str = genMerge.mkOption { type = T.str; };
  t =
    x:
    let
      r = builtins.tryEval (builtins.deepSeq x x);
    in
    if r.success then r.value else "REFUSED";
  schemaOf =
    mods:
    (genMerge.evalModuleTree { } ([ { options.schema = genSchema.mkSchemaOption { }; } ] ++ mods))
    .config.schema;
  leafs = lib.mapAttrs (
    _: v:
    if v ? _type && v._type == "option" then
      {
        t = v.type.name or null;
        d = v.declarations or null;
      }
    else
      leafs v
  );
  names = o: builtins.filter (x: x != "_module") (builtins.attrNames o);
  inst =
    kind: defs:
    (genMerge.evalModuleTree { } [
      { options.h = genMerge.mkOption { type = genSchema.mkInstanceType { } kind; }; }
      { config.h = defs; }
    ]).config.h;
  engine =
    kind: cfg:
    (genMerge.evalModuleTree { } [
      kind
      { config = cfg; }
    ]).config;

  shape =
    s:
    let
      k = 5;
      ks = map (i: "k${toString i}") (lib.range 1 k);
      optsOf = kn: lib.genAttrs (map (o: "${kn}o${toString o}") (lib.range 1 4)) (_: str);
      idx = kn: lib.toInt (lib.removePrefix "k" kn);
      fnAt = i: s == "fn" || (s == "mixed" && lib.mod i 2 == 1);
      extra =
        i:
        if s == "sealed" && i == 1 then
          {
            k1sub = genMerge.mkOption {
              type = T.submodule { options.x = str; };
              default = { };
            };
          }
        else if s == "libstr" && i == 1 then
          { k1np = genMerge.mkOption { type = lib.types.str; }; }
        else if s == "redeclare" && i > 1 then
          { k1o1 = str; }
        else
          { };
      entry =
        config: kn:
        let
          i = idx kn;
        in
        (
          if fnAt i then
            { imports = [ ({ options, ... }: { options = optsOf kn; }) ]; }
          else
            { options = optsOf kn // extra i; }
        )
        // lib.optionalAttrs (i > 1) {
          inherits = [
            config.schema."k${toString (i - 1)}"
          ]
          ++ lib.optional (s == "diamond" && i > 2) config.schema."k${toString (i - 2)}";
        };
      sch = schemaOf [ ({ config, ... }: { config.schema = lib.genAttrs ks (entry config); }) ];
      allOpts = lib.concatMap (kn: builtins.attrNames (optsOf kn)) ks;
      cfg = lib.genAttrs allOpts (o: "${o}-v");
      last = sch."k${toString k}";
    in
    {
      kinds = lib.genAttrs ks (
        kn:
        t {
          opts = leafs (builtins.removeAttrs sch.${kn}.options [ "_module" ]);
          refs = builtins.attrNames sch.${kn}.refs;
          refinements = builtins.attrNames sch.${kn}.refinements;
        }
      );
      host = t (map (o: (inst last cfg).${o}) allOpts);
      gen = t (map (o: (engine last cfg).${o}) allOpts);
    };

  fan =
    disjoint: n:
    let
      perms =
        xs:
        if xs == [ ] then [ [ ] ] else lib.concatMap (x: map (p: [ x ] ++ p) (perms (lib.remove x xs))) xs;
      bs = map (i: "b${toString i}") (lib.range 1 n);
      row =
        order:
        let
          sch = schemaOf [
            {
              config.schema =
                lib.optionalAttrs (!disjoint) { a.options.ao = str; }
                // lib.genAttrs bs (b: {
                  options."${b}o" = str;
                  inherits = lib.optional (!disjoint) "a";
                })
                // {
                  d = {
                    options.dO = str;
                    inherits = map (i: "b${toString i}") order;
                  };
                };
            }
          ];
          ns = names sch.d.options;
          cfg = lib.genAttrs ns (o: "${o}-v");
        in
        {
          name = lib.concatStrings (map toString order);
          value = {
            opts = t ns;
            anc = t (map (k: k.kind) (genSchema.ancestorsForKind sch.d));
            gen = t (map (o: (engine sch.d cfg).${o}) ns);
          };
        };
    in
    builtins.listToAttrs (map row (perms (lib.range 1 n)));

  honest =
    let
      intOpt = genMerge.mkOption { type = T.int; };
      schemaWith =
        edit:
        schemaOf [
          { config.schema.host.options.port = intOpt; }
          (
            { config, ... }:
            {
              config.schema.sub = {
                inherits = [ (edit config.schema.host) ];
                options.x = intOpt;
              };
            }
          )
        ];
      opts = k: builtins.attrNames (genMerge.evalModuleTree { } [ k ]).options;
      edited = schemaWith (
        h:
        h
        // {
          options = h.options // {
            extra = intOpt;
          };
        }
      );
    in
    [
      (t (opts (schemaWith (h: h)).sub))
      (t (opts edited.sub))
      (t (
        builtins.attrNames (
          inst edited.sub {
            port = 1;
            x = 2;
          }
        )
      ))
      (t
        (inst edited.sub {
          port = 1;
          x = 2;
          extra = 3;
        }).extra
      )
      (t (builtins.isString edited.sub.__mint.minted))
    ];

  forgedWith =
    fileName:
    let
      sch = schemaOf [
        (
          { config, ... }:
          {
            config.schema = {
              k1.options.a = str;
              k2 = {
                options.b = str;
                inherits = [ config.schema.k1 ];
              };
              k3 = {
                options.c = str;
                inherits = [ config.schema.k2 ];
              };
            };
          }
        )
        {
          _file = fileName;
          config.schema.k2.options.extra = str;
        }
      ];
    in
    {
      k2 = t (names sch.k2.options);
      k3 = t (names sch.k3.options);
      inst =
        t
          (inst sch.k2 {
            a = "1";
            b = "2";
            extra = "3";
          }).extra;
    };

  key =
    let
      sch = schemaOf [
        {
          config.schema = {
            p = {
              key = "X";
              options.a = str;
            };
            c = {
              key = "X";
              options.b = str;
              inherits = [ "p" ];
            };
          };
        }
      ];
    in
    t (names sch.c.options);

  methods =
    let
      sch = schemaOf [
        {
          config.schema = {
            p.options.a = str;
            c = {
              options.b = str;
              inherits = [ "p" ];
              methods.label = genSchema.schemaFn {
                description = "Label";
                type = T.str;
                fn = { b, ... }: "c:${b}";
              };
            };
          };
        }
      ];
    in
    {
      opts = t (names sch.c.options);
      label =
        t
          (engine sch.c {
            a = "1";
            b = "2";
          }).label;
    };

  fnParent =
    let
      sch = schemaOf [
        {
          config.schema = {
            p.imports = [
              (
                { config, ... }:
                {
                  options.y = genMerge.mkOption {
                    type = T.str;
                    default = config.x or "none";
                  };
                }
              )
            ];
            c = {
              options.x = genMerge.mkOption {
                type = T.str;
                default = "cx";
              };
              inherits = [ "p" ];
            };
          };
        }
      ];
    in
    {
      opts = t (names sch.c.options);
      y = t sch.c.options.y.default;
    };
in
lib.genAttrs [
  "chain"
  "fn"
  "mixed"
  "diamond"
  "sealed"
  "libstr"
  "redeclare"
] (s: shape s)
// {
  fan-shared = lib.genAttrs [ "2" "3" "4" ] (n: fan false (lib.toInt n));
  fan-disjoint = lib.genAttrs [ "2" "3" "4" ] (n: fan true (lib.toInt n));
  inherit
    honest
    key
    methods
    fnParent
    ;
  forged = forgedWith "<gen-schema evalSchema: kind 'k2' inherits 'zz'>";
  forged-control = forgedWith "an-ordinary-file.nix";
}
