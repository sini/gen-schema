{
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) evalSchema mkInstanceRegistry declarationOf;
  t = genMerge.types;

  # A kind option whose submodule's module set reads back into the registry being built (den-hoag-dqw5z):
  # its imports are a function of every host's value. The completion stamp compares the kind's `refs`
  # at the first instance import, and `refs` asks every option type whether it carries a ref, so a
  # reading of the submodule's `nestedTypes` (its own module set evaluated) re-enters the registry.
  schema = evalSchema { } [
    {
      config.schema.host = {
        options.addr = genMerge.mkOption { type = t.str; };
        options.settings = genMerge.mkOption {
          type = t.submodule {
            imports = map (h: {
              options."peer-${h.name}" = genMerge.mkOption {
                type = t.str;
                default = h.addr;
              };
            }) (builtins.attrValues eval.config.hosts);
          };
          default = { };
        };
      };
      config.schema.service = {
        options.hosts = genMerge.mkOption {
          type = t.nullOr (t.listOf (declarationOf "host"));
          default = null;
        };
        options.extra = genMerge.mkOption {
          type = t.listOf (t.submodule { options.port = genMerge.mkOption { type = t.int; }; });
          default = [ ];
        };
      };
    }
  ];

  eval = genMerge.evalModuleTree { } [
    {
      options.hosts = mkInstanceRegistry { } schema.host;
      options.services = mkInstanceRegistry { refs.hosts = eval.config.hosts; } schema.service;
      config.hosts.igloo.addr = "10.0.1.1";
      config.hosts.iceberg.addr = "10.0.1.2";
      config.services.web.hosts = [ "iceberg" ];
    }
  ];
in
{
  flake.tests.ref-submodule-knot = {
    test-knot-evaluates = {
      expr = eval.config.hosts.igloo.settings;
      expected = {
        peer-iceberg = "10.0.1.2";
        peer-igloo = "10.0.1.1";
      };
    };
    test-submodule-option-carries-no-ref = {
      expr = schema.host.refs;
      expected = { };
    };
    # The element reading still reaches a ref through the wrappers, beside a submodule element that has none.
    test-wrapped-ref-still-read = {
      expr = builtins.mapAttrs (_: r: r.refKind) schema.service.refs;
      expected.hosts = "host";
    };
    test-wrapped-ref-binds = {
      expr = map (h: h.addr) eval.config.services.web.hosts;
      expected = [ "10.0.1.2" ];
    };
  };
}
