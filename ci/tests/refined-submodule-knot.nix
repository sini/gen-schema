{
  genSchema,
  genMerge,
  lib,
  ...
}:
let
  inherit (genSchema)
    evalSchema
    mkInstanceRegistry
    declarationOf
    refined
    ;
  t = genMerge.types;

  # ref-submodule-knot's shape under `refined` (den-hoag-60hql): a kind option typed by a refined
  # submodule whose module set reads back into the registry being built. `refined` copies its base
  # into gen-merge's `mkOptionType`, and the door used to read the copy's `nestedTypes` (the module set
  # evaluated) for its roles, reached from the kind's `refs` read: an uncatchable recursion. gen-merge's
  # `evaluatesOwnRoles` now recognises any record carrying `carries.moduleSet`, so the base is a gen
  # submodule or one gen-merge imported from nixpkgs (`mkOptionType (lib.types.submodule …)`). Every
  # refinement here that is read at construction is lazy, or the read is the kind's `refs`: a strict
  # refinement demands the field when the instance is built, a second knot this file does not cover.
  # A raw nixpkgs `submodule` base still recurses (the residue, README's `refined` section).
  r = {
    check = _: true;
    message = "never";
  };
  rLazy = r // {
    lazy = true;
  };
  peersOf = hosts: {
    imports = map (h: {
      options."peer-${h.name}" = genMerge.mkOption {
        type = t.str;
        default = h.addr;
      };
    }) (builtins.attrValues hosts);
  };
  nixPeersOf = hosts: {
    imports = map (h: {
      options."peer-${h.name}" = lib.mkOption {
        type = lib.types.str;
        default = h.addr;
      };
    }) (builtins.attrValues hosts);
  };

  knot =
    {
      wrap,
      def ? null,
    }:
    let
      schema = evalSchema { } [
        {
          config.schema.host = {
            options.addr = genMerge.mkOption { type = t.str; };
            options.settings = genMerge.mkOption {
              type = wrap eval.config.hosts;
              default = { };
            };
          };
          config.schema.service = {
            options.hosts = genMerge.mkOption {
              type = t.nullOr (t.listOf (declarationOf "host"));
              default = null;
            };
          };
        }
      ];
      eval = genMerge.evalModuleTree { } (
        [
          {
            options.hosts = mkInstanceRegistry { } schema.host;
            options.services = mkInstanceRegistry { refs.hosts = eval.config.hosts; } schema.service;
            config.hosts.igloo.addr = "10.0.1.1";
            config.hosts.iceberg.addr = "10.0.1.2";
            config.services.web.hosts = [ "iceberg" ];
          }
        ]
        ++ lib.optional (def != null) { config.hosts.igloo.settings = def; }
      );
    in
    {
      addr = eval.config.hosts.igloo.addr;
      inherit (eval.config.hosts.igloo) settings;
      refs = builtins.attrNames schema.host.refs;
      svc = map (h: h.addr) eval.config.services.web.hosts;
    };

  sub = hosts: t.submodule (peersOf hosts);
  imported = hosts: genMerge.mkOptionType (lib.types.submodule (nixPeersOf hosts));
  peers = {
    peer-iceberg = "10.0.1.2";
    peer-igloo = "10.0.1.1";
  };
in
{
  flake.tests.refined-submodule-knot = {
    # the gen submodule base: the K population
    test-a-refined-submodule-knot-composes = {
      expr = {
        attrsRefinedAddr = (knot { wrap = h: t.attrsOf (refined (sub h) [ r ]); }).addr;
        attrsRefinedSettings = (knot { wrap = h: t.attrsOf (refined (sub h) [ r ]); }).settings;
        attrsRefinedDefined =
          (knot {
            wrap = h: t.attrsOf (refined (sub h) [ r ]);
            def.e1 = { };
          }).settings;
        attrsRefinedLazyAddr = (knot { wrap = h: t.attrsOf (refined (sub h) [ rLazy ]); }).addr;
        refinedLazyAddr = (knot { wrap = h: refined (sub h) [ rLazy ]; }).addr;
        refinedLazySettings = (knot { wrap = h: refined (sub h) [ rLazy ]; }).settings;
        refinedRefs = (knot { wrap = h: refined (sub h) [ r ]; }).refs;
        refinedSvc = (knot { wrap = h: refined (sub h) [ rLazy ]; }).svc;
      };
      expected = {
        attrsRefinedAddr = "10.0.1.1";
        attrsRefinedSettings = { };
        attrsRefinedDefined.e1 = peers;
        attrsRefinedLazyAddr = "10.0.1.1";
        refinedLazyAddr = "10.0.1.1";
        refinedLazySettings = peers;
        refinedRefs = [ ];
        refinedSvc = [ "10.0.1.2" ];
      };
    };
    # a nixpkgs submodule gen-merge imported: the record carries `carries.moduleSet` and no `nests`
    test-a-refined-imported-submodule-knot-composes = {
      expr = {
        refinedLazyAddr = (knot { wrap = h: refined (imported h) [ rLazy ]; }).addr;
        refinedLazySettings = (knot { wrap = h: refined (imported h) [ rLazy ]; }).settings;
        refinedRefs = (knot { wrap = h: refined (imported h) [ r ]; }).refs;
        attrsRefinedAddr = (knot { wrap = h: t.attrsOf (refined (imported h) [ r ]); }).addr;
        doorDoorSettings = (knot { wrap = h: genMerge.mkOptionType (imported h); }).settings;
      };
      expected = {
        refinedLazyAddr = "10.0.1.1";
        refinedLazySettings = peers;
        refinedRefs = [ ];
        attrsRefinedAddr = "10.0.1.1";
        doorDoorSettings = peers;
      };
    };
    # constructing `refined` over a submodule never evaluates its module set
    test-refined-never-evaluates-the-module-set = {
      expr =
        let
          ok = x: (builtins.tryEval (builtins.seq x true)).success;
          P.imports = throw "refined-submodule-knot: module set evaluated 7b2e51c4";
        in
        {
          gen = ok (refined (t.submodule P) [ r ]);
          imported = ok (refined (genMerge.mkOptionType (lib.types.submodule P)) [ r ]);
        };
      expected = {
        gen = true;
        imported = true;
      };
    };
  };
}
