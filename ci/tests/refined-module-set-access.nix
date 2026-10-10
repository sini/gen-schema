{
  genSchema,
  genMerge,
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

  # A strict refinement on a field that carries a module set at any carried depth is checked at
  # access; a field carrying none keeps construction-time checking. The host kind's `settings` is
  # `wrap (submodule ms)`, with `ms` the knot (one option per host of the registry being built) or a
  # static set, unless `decl` declares `settings` otherwise (an option group over the submodule, or a
  # type carrying none); `ports` is a non-flat field carrying no module set. Every value cell reads a
  # value or "REFUSED" (`tryEval` over `deepSeq`); the `testsError` cells pin which refusal fired at
  # access.
  tr =
    e:
    let
      r = builtins.tryEval (builtins.deepSeq e e);
    in
    if r.success then r.value else "REFUSED";
  pass = {
    check = _: true;
    message = "never";
  };
  fail = {
    check = _: false;
    message = "always fails";
  };
  # a strict refinement that forces the whole value, and so any module tree it carries
  deep = {
    check = v: builtins.deepSeq v true;
    message = "deep";
  };
  knotMs = hosts: {
    imports = map (h: {
      options."peer-${h.name}" = genMerge.mkOption {
        type = t.str;
        default = h.addr;
      };
    }) (builtins.attrValues hosts);
  };
  staticMs = _: {
    options.peer-static = genMerge.mkOption {
      type = t.str;
      default = "s";
    };
  };
  host =
    {
      wrap ? (s: s),
      ms ? staticMs,
      refinements ? { },
      decl ? (
        s:
        genMerge.mkOption {
          type = wrap s;
          default = { };
        }
      ),
    }:
    let
      schema = evalSchema { } [
        {
          config.schema.host = {
            options.addr = genMerge.mkOption { type = t.str; };
            options.ports = genMerge.mkOption {
              type = t.listOf t.int;
              default = [ 1 ];
            };
            options.settings = decl (t.submodule (ms eval.config.hosts));
          };
          config.schema.service = {
            options.hosts = genMerge.mkOption {
              type = t.nullOr (t.listOf (declarationOf "host"));
              default = null;
            };
          };
        }
      ];
      eval = genMerge.evalModuleTree { } [
        {
          options.hosts = mkInstanceRegistry { inherit refinements; } schema.host;
          options.services = mkInstanceRegistry { refs.hosts = eval.config.hosts; } schema.service;
          config.hosts.igloo.addr = "10.0.1.1";
          config.hosts.iceberg.addr = "10.0.1.2";
          config.services.web.hosts = [ "iceberg" ];
        }
      ];
    in
    eval.config.hosts.igloo // { svc = map (h: h.addr) eval.config.services.web.hosts; };
  # `settings` as an option group: its value carries the module tree one level down
  group = s: {
    inner = genMerge.mkOption {
      type = s;
      default = { };
    };
  };
  # a self-referential type carrying no module set (nixpkgs' `types.json` shape), and a finite nest
  json =
    _:
    genMerge.mkOption {
      type =
        let
          v = t.nullOr (t.either t.int (t.attrsOf v));
        in
        v;
      default.a = 1;
    };
  finiteNest =
    _:
    genMerge.mkOption {
      type = t.nullOr (t.attrsOf (t.listOf (t.attrsOf t.int)));
      default.a = [ { b = 1; } ];
    };
  failOn = f: { ${f} = [ fail ]; };
  passOn = f: { ${f} = [ pass ]; };
  peers = {
    peer-iceberg = "10.0.1.2";
    peer-igloo = "10.0.1.1";
  };
in
{
  flake.tests.refined-module-set-access = {
    # A failing strict refinement on a field carrying a module set refuses that field's read, and
    # its siblings serve: as a type refinement, as a registry refinement, and with the module set
    # under `nullOr`, `attrsOf`, `either`, or nested past gen-merge's type-walk fuel (33 deep).
    test-a-failing-refinement-on-a-module-set-field-refuses-at-access = {
      expr = builtins.mapAttrs (_: tr) {
        typeSibling = (host { wrap = s: refined s [ fail ]; }).addr;
        typeField = (host { wrap = s: refined s [ fail ]; }).settings;
        typeOtherSibling = (host { wrap = s: refined s [ fail ]; }).ports;
        passSibling = (host { refinements = failOn "settings"; }).addr;
        passField = (host { refinements = failOn "settings"; }).settings;
        nullOrSibling =
          (host {
            wrap = t.nullOr;
            refinements = failOn "settings";
          }).addr;
        nullOrField =
          (host {
            wrap = t.nullOr;
            refinements = failOn "settings";
          }).settings;
        attrsOfSibling =
          (host {
            wrap = t.attrsOf;
            refinements = failOn "settings";
          }).addr;
        eitherSibling =
          (host {
            wrap = t.either t.str;
            refinements = failOn "settings";
          }).addr;
        eitherField =
          (host {
            wrap = t.either t.str;
            refinements = failOn "settings";
          }).settings;
        pastFuelSibling =
          (host {
            wrap = s: builtins.foldl' (acc: _: t.nullOr acc) s (builtins.genList (x: x) 33);
            refinements = failOn "settings";
          }).addr;
      };
      expected = {
        typeSibling = "10.0.1.1";
        typeField = "REFUSED";
        typeOtherSibling = [ 1 ];
        passSibling = "10.0.1.1";
        passField = "REFUSED";
        nullOrSibling = "10.0.1.1";
        nullOrField = "REFUSED";
        attrsOfSibling = "10.0.1.1";
        eitherSibling = "10.0.1.1";
        eitherField = "REFUSED";
        pastFuelSibling = "10.0.1.1";
      };
    };
    # A failing strict refinement on a field carrying no module set is decided at construction, so
    # a sibling read refuses too: a flat field (`addr`) and a non-flat one (`ports`, `listOf int`).
    test-a-failing-refinement-on-a-field-carrying-no-module-set-refuses-at-construction = {
      expr = builtins.mapAttrs (_: tr) {
        flatSibling = (host { refinements = failOn "addr"; }).settings;
        flatField = (host { refinements = failOn "addr"; }).addr;
        listSibling = (host { refinements = failOn "ports"; }).addr;
        listField = (host { refinements = failOn "ports"; }).ports;
      };
      expected = {
        flatSibling = "REFUSED";
        flatField = "REFUSED";
        listSibling = "REFUSED";
        listField = "REFUSED";
      };
    };
    # A strict refinement on a field whose module set reads back into the registry being built
    # composes: a refined type (once, twice, refined over refined), a registry refinement on the bare
    # submodule, and one on the submodule under `nullOr` or `either`.
    test-a-strict-refinement-on-a-registry-reading-module-set-composes = {
      expr = {
        typeAddr =
          (host {
            wrap = s: refined s [ pass ];
            ms = knotMs;
          }).addr;
        typeSettings =
          (host {
            wrap = s: refined s [ pass ];
            ms = knotMs;
          }).settings;
        typeSvc =
          (host {
            wrap = s: refined s [ pass ];
            ms = knotMs;
          }).svc;
        typeTwice =
          (host {
            wrap =
              s:
              refined s [
                pass
                pass
              ];
            ms = knotMs;
          }).addr;
        typeRefinedRefined =
          (host {
            wrap = s: refined (refined s [ pass ]) [ pass ];
            ms = knotMs;
          }).addr;
        passAddr =
          (host {
            refinements = passOn "settings";
            ms = knotMs;
          }).addr;
        passSettings =
          (host {
            refinements = passOn "settings";
            ms = knotMs;
          }).settings;
        nullOrAddr =
          (host {
            wrap = t.nullOr;
            refinements = passOn "settings";
            ms = knotMs;
          }).addr;
        eitherAddr =
          (host {
            wrap = t.either t.str;
            refinements = passOn "settings";
            ms = knotMs;
          }).addr;
      };
      expected = {
        typeAddr = "10.0.1.1";
        typeSettings = peers;
        typeSvc = [ "10.0.1.2" ];
        typeTwice = "10.0.1.1";
        typeRefinedRefined = "10.0.1.1";
        passAddr = "10.0.1.1";
        passSettings = peers;
        nullOrAddr = "10.0.1.1";
        eitherAddr = "10.0.1.1";
      };
    };
    # A field declared as an option group carries the module set of an option beneath it, so a
    # failing strict refinement on it refuses only that field's read.
    test-a-failing-refinement-on-a-module-set-option-group-refuses-at-access = {
      expr = builtins.mapAttrs (_: tr) {
        groupSibling =
          (host {
            decl = group;
            refinements = failOn "settings";
          }).addr;
        groupField =
          (host {
            decl = group;
            refinements = failOn "settings";
          }).settings;
      };
      expected = {
        groupSibling = "10.0.1.1";
        groupField = "REFUSED";
      };
    };
    # A strict refinement forcing an option group whose module set reads back into the registry
    # being built composes, as it does on the bare submodule.
    test-a-strict-refinement-on-a-registry-reading-option-group-composes = {
      expr = {
        groupAddr =
          (host {
            decl = group;
            refinements.settings = [ deep ];
            ms = knotMs;
          }).addr;
        groupSettings =
          (host {
            decl = group;
            refinements.settings = [ deep ];
            ms = knotMs;
          }).settings;
      };
      expected = {
        groupAddr = "10.0.1.1";
        groupSettings.inner = peers;
      };
    };
    # A self-referential type never ends, so the walk exhausts gen-merge's bound and the field is
    # checked at access although its value is flat: a failing refinement on it refuses only that
    # field's read. A finite nest of the same containers is walked to its end and keeps
    # construction-time checking.
    test-a-self-referential-type-exhausts-the-walk-and-is-checked-at-access = {
      expr = builtins.mapAttrs (_: tr) {
        selfRefSibling =
          (host {
            decl = json;
            refinements = failOn "settings";
          }).addr;
        selfRefField =
          (host {
            decl = json;
            refinements = failOn "settings";
          }).settings;
        finiteNestSibling =
          (host {
            decl = finiteNest;
            refinements = failOn "settings";
          }).addr;
        finiteNestField =
          (host {
            decl = finiteNest;
            refinements = failOn "settings";
          }).settings;
      };
      expected = {
        selfRefSibling = "10.0.1.1";
        selfRefField = "REFUSED";
        finiteNestSibling = "REFUSED";
        finiteNestField = "REFUSED";
      };
    };
  };
}
