# attrsOf / lazyAttrsOf over a declaration on a BOUND kind field: the registry binding walks them (bindRefType)
# and the coerce chain maps the per-value coercion over the set (mkCoerceChain), with each value a scalar
# position. Refusals of the containers that are still not walked live in ../tests-error.nix.
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
    setOf
    refined
    ;
  T = genMerge.types;
  D = declarationOf "host";

  # Read field f of an svc bound to `type`, instances rendered as their names.
  show =
    v:
    if builtins.isList v then
      map show v
    else if builtins.isAttrs v && v ? id_hash then
      v.name
    else if builtins.isAttrs v then
      builtins.mapAttrs (_: show) v
    else
      v;
  read =
    {
      type,
      value,
      bind ? (hosts: hosts),
      kindOf ? "host",
    }:
    let
      schema = evalSchema {
        modules = [
          {
            config.schema.host = { };
            config.schema.svc.options.f = genMerge.mkOption { inherit type; };
          }
        ];
      };
    in
    show
      (genMerge.evalModuleTree { } [
        (
          { config, ... }:
          {
            options.hosts = mkInstanceRegistry schema.host { };
            options.svcs = mkInstanceRegistry schema.svc { refs.f = bind config.hosts; };
            config.hosts.a = { };
            config.hosts.b = { };
            config.svcs.s.f = value;
          }
        )
      ]).config.svcs.s.f;
  xy = {
    x = "a";
    y = "b";
  };
in
{
  flake.tests.ref-attrsof = {
    test-attrsof = {
      expr = read {
        type = T.attrsOf D;
        value = xy;
      };
      expected = xy;
    };
    test-lazyattrsof = {
      expr = read {
        type = T.lazyAttrsOf D;
        value = xy;
      };
      expected = xy;
    };
    test-attrsof-empty = {
      expr = read {
        type = T.attrsOf D;
        value = { };
      };
      expected = { };
    };
    test-attrsof-nullor = {
      expr = read {
        type = T.attrsOf (T.nullOr D);
        value = {
          x = "a";
          y = null;
        };
      };
      expected = {
        x = "a";
        y = null;
      };
    };
    test-attrsof-listof = {
      expr = read {
        type = T.attrsOf (T.listOf D);
        value.x = [
          "a"
          "b"
        ];
      };
      expected.x = [
        "a"
        "b"
      ];
    };
    test-attrsof-setof-dedups = {
      expr = read {
        type = T.attrsOf (setOf D);
        value.x = [
          "a"
          "a"
        ];
      };
      expected.x = [ "a" ];
    };
    test-attrsof-attrsof = {
      expr = read {
        type = T.attrsOf (T.attrsOf D);
        value.x.y = "a";
      };
      expected.x.y = "a";
    };
    test-listof-attrsof = {
      expr = read {
        type = T.listOf (T.attrsOf D);
        value = [ { x = "a"; } ];
      };
      expected = [ { x = "a"; } ];
    };
    test-nullor-attrsof = {
      expr = read {
        type = T.nullOr (T.attrsOf D);
        value.x = "a";
      };
      expected.x = "a";
    };
    test-nullor-attrsof-null = {
      expr = read {
        type = T.nullOr (T.attrsOf D);
        value = null;
      };
      expected = null;
    };
    test-refined-attrsof = {
      expr = read {
        type = refined (T.attrsOf D) [ ];
        value.x = "a";
      };
      expected.x = "a";
    };
    test-attrsof-three-deep = {
      expr = read {
        type = T.attrsOf (T.listOf (T.nullOr D));
        value.x = [
          "a"
          null
        ];
      };
      expected.x = [
        "a"
        null
      ];
    };
    test-attrsof-scalar-custom-coerce = {
      expr = read {
        type = T.attrsOf D;
        value.x = "a";
        bind = hosts: {
          instances = hosts;
          coerce = default: _: default;
        };
      };
      expected.x = "a";
    };
    test-attrsof-deferred-binding = {
      expr = read {
        type = T.attrsOf (declarationOf "svc");
        value.x = "s";
        bind = hosts: {
          deferred = true;
          instances = hosts;
        };
      };
      expected.x = "s";
    };
    # The key set is untouched, so a lazy key stays unforced until read.
    test-lazyattrsof-dangling-key-unread = {
      expr =
        (read {
          type = T.lazyAttrsOf D;
          value = {
            x = "a";
            y = "nope";
          };
        }).x;
      expected = "a";
    };
    # Controls: the walked wrappers that were served before.
    test-control-scalar = {
      expr = read {
        type = D;
        value = "a";
      };
      expected = "a";
    };
    test-control-listof = {
      expr = read {
        type = T.listOf D;
        value = [
          "a"
          "b"
        ];
      };
      expected = [
        "a"
        "b"
      ];
    };
    test-control-setof-dedups = {
      expr = read {
        type = setOf D;
        value = [
          "a"
          "a"
          "b"
        ];
      };
      expected = [
        "a"
        "b"
      ];
    };
    test-control-listof-nullor = {
      expr = read {
        type = T.listOf (T.nullOr D);
        value = [
          "a"
          null
        ];
      };
      expected = [
        "a"
        null
      ];
    };
  };
}
