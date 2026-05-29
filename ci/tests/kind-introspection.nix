# Kind-level introspection: options, refs, strict live on each kind result.
# _kindMeta and _strict are removed from schema root.
{
  lib,
  genSchema,
  ...
}:
let
  inherit (genSchema) mkSchemaOption ref;

  eval = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption { };
        config.schema.host = {
          options.name = lib.mkOption { type = lib.types.str; };
          options.addr = lib.mkOption { type = lib.types.str; };
        };
        config.schema.service = {
          options.port = lib.mkOption { type = lib.types.int; };
          options.host = lib.mkOption { type = ref "host"; };
        };
      }
    ];
  };

  host = eval.config.schema.host;
  service = eval.config.schema.service;
in
{
  flake.tests.kind-introspection = {
    # options is present and excludes _module.* attrs
    test-host-has-options = {
      expr = host ? options;
      expected = true;
    };
    test-host-options-has-name = {
      expr = host.options ? name;
      expected = true;
    };
    test-host-options-has-addr = {
      expr = host.options ? addr;
      expected = true;
    };
    test-host-options-no-module-args = {
      expr = lib.any (n: lib.hasPrefix "_module" n) (lib.attrNames host.options);
      expected = false;
    };

    # refs is present with enriched shape
    test-host-has-refs = {
      expr = host ? refs;
      expected = true;
    };
    test-host-refs-empty = {
      expr = host.refs;
      expected = { };
    };
    test-service-refs-has-host = {
      expr = service.refs ? host;
      expected = true;
    };
    test-service-refs-shape = {
      expr = service.refs.host.refKind;
      expected = "host";
    };
    test-service-refs-has-type = {
      expr = service.refs.host ? type;
      expected = true;
    };

    # strict defaults to true
    test-host-has-strict = {
      expr = host ? strict;
      expected = true;
    };
    test-host-strict-default = {
      expr = host.strict;
      expected = true;
    };

    # _kindMeta and _strict are gone from schema root
    test-no-kindMeta = {
      expr = eval.config.schema ? _kindMeta;
      expected = false;
    };
    test-no-strict = {
      expr = eval.config.schema ? _strict;
      expected = false;
    };

    # topology/edges still work
    test-kind-names = {
      expr = eval.config.schema._kindNames;
      expected = [
        "host"
        "service"
      ];
    };
    test-ref-edges = {
      expr = builtins.length eval.config.schema._refEdges;
      expected = 1;
    };
    test-ref-edge-to = {
      expr = (builtins.head eval.config.schema._refEdges).to;
      expected = "host";
    };
  };
}
