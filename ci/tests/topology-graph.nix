# den-hoag-4kh.53.51. The containment topology is gen-graph's computation, and its answers are the
# ones the hand-rolled folds it replaced gave.
#
# The DELEGATION cell is the only one that can tell "computed by gen-graph" from "computed
# equivalently": the library is built with the real gen-graph whose four consumed surfaces return
# sentinels, and every sentinel must surface in the schema's introspection. A surface computed here
# instead answers its own value and reads false.
#
# The PARITY cells pin two properties the rest of the suite does not: children in kind-name order on
# a wide container, and an undeclared parent refusing a read of an UNRELATED kind's topology (the
# timing the eager fold had).
{
  genSchema,
  genMerge,
  genAlgebra,
  genIdentity,
  genGraph,
  prelude,
  ...
}:
let
  schemaOf =
    gs: modules:
    (genMerge.evalModuleTree {
      modules = [ { options.schema = gs.mkSchemaOption { }; } ] ++ modules;
    }).config.schema;
  kinds = attrs: [ { config.schema = attrs; } ];

  stubbed = import ../../lib {
    inherit prelude;
    merge = genMerge;
    algebra = genAlgebra;
    identity = genIdentity;
    graph = genGraph // {
      materializeParents = _: { user = "PARENT-SENTINEL"; };
      directDependents = _: { host = [ "CHILD-SENTINEL" ]; };
      roots = _: [ "ROOT-SENTINEL" ];
      leaves = _: [ "LEAF-SENTINEL" ];
      # The well-foundedness guard's surface; its delegation is pinned in ci/tests-error.nix.
      cycles = _: [ ];
    };
  };
  delegated = schemaOf stubbed (kinds {
    host = { };
    user.parent = "host";
  });

  den = schemaOf genSchema (kinds {
    conf = { };
    fleet = { };
    host = { };
    user.parent = "host";
    home.parent = "host";
  });
  star20 = schemaOf genSchema (
    kinds (
      {
        hub = { };
      }
      // builtins.listToAttrs (
        builtins.genList (i: {
          name = "s${toString i}";
          value.parent = "hub";
        }) 20
      )
    )
  );
  ghost = schemaOf genSchema (kinds {
    x = { };
    y.parent = "ghost";
  });
  # The control: the same read with the parent declared answers.
  declared = schemaOf genSchema (kinds {
    x = { };
    y.parent = "x";
  });
in
{
  flake.tests.topology-graph = {
    test-delegates-every-answer-to-gen-graph = {
      expr = {
        parent = delegated._topology.user.parent;
        children = delegated._topology.host.children;
        roots = delegated._roots;
        leaves = delegated._leaves;
      };
      expected = {
        parent = "PARENT-SENTINEL";
        children = [ "CHILD-SENTINEL" ];
        roots = [ "ROOT-SENTINEL" ];
        leaves = [ "LEAF-SENTINEL" ];
      };
    };
    test-den-roots = {
      expr = den._roots;
      expected = [
        "conf"
        "fleet"
        "host"
      ];
    };
    test-den-leaves = {
      expr = den._leaves;
      expected = [
        "conf"
        "fleet"
        "home"
        "user"
      ];
    };
    test-wide-container-children-in-kind-name-order = {
      expr = star20._topology.hub.children;
      expected = [
        "s0"
        "s1"
        "s10"
        "s11"
        "s12"
        "s13"
        "s14"
        "s15"
        "s16"
        "s17"
        "s18"
        "s19"
        "s2"
        "s3"
        "s4"
        "s5"
        "s6"
        "s7"
        "s8"
        "s9"
      ];
    };
    test-undeclared-parent-refuses-an-unrelated-read = {
      expr = map (s: builtins.tryEval s._topology.x.parent) [
        ghost
        declared
      ];
      expected = [
        {
          success = false;
          value = false;
        }
        {
          success = true;
          value = null;
        }
      ];
    };
    # The well-foundedness guard sits on each ENTRY: the spine of `_topology` is the kind names and
    # answers on a schema whose containment refuses, as it did before the guard.
    test-undeclared-parent-leaves-the-topology-spine-answering = {
      expr = {
        names = builtins.attrNames ghost._topology;
        has = ghost._topology ? x;
      };
      expected = {
        names = [
          "x"
          "y"
        ];
        has = true;
      };
    };
  };
}
