{
  genSchema,
  genMerge,
  lib,
  ...
}:
let
  inherit (genSchema) evalSchema mkInstanceRegistry declarationOf;
  t = genMerge.types;
  nt = lib.types;

  # ref-submodule-knot's shape over NIXPKGS types (den-hoag-gi421): a kind option typed by a nixpkgs
  # `submodule` / `submoduleWith` whose module set reads back into the registry being built. A foreign
  # submodule's `nestedTypes` is its own module set evaluated too, so `refs` reads its element through
  # gen-merge's `importedCarried`, which never reads that field.
  peers = map (h: {
    options."peer-${h.name}" = lib.mkOption {
      type = nt.str;
      default = h.addr;
    };
  }) (builtins.attrValues eval.config.hosts);

  schema = evalSchema { } [
    {
      config.schema.host = {
        options.addr = genMerge.mkOption { type = t.str; };
        options.settings = genMerge.mkOption {
          type = nt.submodule { imports = peers; };
          default = { };
        };
        options.settingsWith = genMerge.mkOption {
          type = nt.submoduleWith { modules = peers; };
          default = { };
        };
      };
      config.schema.service = {
        options.hosts = genMerge.mkOption {
          type = nt.nullOr (nt.listOf (declarationOf "host"));
          default = null;
        };
        options.byRole = genMerge.mkOption {
          type = nt.attrsOf (declarationOf "host");
          default = { };
        };
      };
    }
  ];

  eval = genMerge.evalModuleTree { } [
    {
      options.hosts = mkInstanceRegistry { } schema.host;
      options.services = mkInstanceRegistry {
        refs.hosts = eval.config.hosts;
        refs.byRole = eval.config.hosts;
      } schema.service;
      config.hosts.igloo.addr = "10.0.1.1";
      config.hosts.iceberg.addr = "10.0.1.2";
      config.services.web.hosts = [ "iceberg" ];
      config.services.web.byRole.primary = "igloo";
    }
  ];
  peersExpected = {
    peer-iceberg = "10.0.1.2";
    peer-igloo = "10.0.1.1";
  };
in
{
  flake.tests.ref-foreign-submodule-knot = {
    test-submodule-knot-evaluates = {
      expr = eval.config.hosts.igloo.settings;
      expected = peersExpected;
    };
    test-submoduleWith-knot-evaluates = {
      expr = eval.config.hosts.igloo.settingsWith;
      expected = peersExpected;
    };
    test-foreign-submodule-carries-no-ref = {
      expr = schema.host.refs;
      expected = { };
    };
    # A ref is still read through nixpkgs containers that carry one.
    test-foreign-wrapped-ref-still-read = {
      expr = builtins.mapAttrs (_: r: r.refKind) schema.service.refs;
      expected = {
        hosts = "host";
        byRole = "host";
      };
    };
    test-foreign-wrapped-ref-binds = {
      expr = {
        hosts = map (h: h.addr) eval.config.services.web.hosts;
        byRole = builtins.mapAttrs (_: h: h.addr) eval.config.services.web.byRole;
      };
      expected = {
        hosts = [ "10.0.1.2" ];
        byRole.primary = "10.0.1.1";
      };
    };
  };
}
