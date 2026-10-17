{
  genSchema,
  genMerge,
  genAlgebra,
  ...
}:
let
  F = import ../test-fixtures/collection-in-identity.nix { inherit genSchema genMerge genAlgebra; };
  plain = F.shapeTree "plain";

  # den-hoag-9zyp7: a kind keeps a collection in its identity whose contents read an instance the kind
  # types (den#719's shape, undeclared). The instance's import reads the content stamp alone, so it
  # demands no identity, and each read serves. Red at the base library on Nix and Determinate
  # (`infinite recursion`); Lix served these four there, so a Lix-only run cannot tell the arms apart.
  # The refusals are `collection-in-identity-refusals` in ./tests-error.nix.
  copyServes = s: mode: {
    "test-${s}-${mode}-copy-instance-reads-the-honest-value" = {
      expr = (F.copyTree s mode).hosts.igloo.addr;
      expected = "10.0.1.1";
    };
  };
  # den-hoag-c2836: a copy over `__kindAncestors` alone composes at every door that reads content (the
  # instance import, a child by value, a child's `imports`); its identity reads are refused
  # (`collection-in-identity-refusals`).
  ancestorsCopyComposes = door: {
    "test-ancestors-copy-${door}-composes-the-options" = {
      expr = builtins.attrNames (F.ancestorsCopyTree door).schema.kid.options;
      expected = [
        "addr"
        "g"
        "r"
      ];
    };
    "test-ancestors-copy-${door}-instance-reads-the-honest-value" = {
      expr = (F.ancestorsCopyTree door).hosts.igloo.addr;
      expected = "10.0.1.1";
    };
  };
  recomputeAgrees = s: {
    "test-${s}-recompute-is-the-instance-identity" = {
      expr = F.recompute s "none" "own" == (F.copyTree s "none").hosts.igloo.id_hash;
      expected = true;
    };
  };
in
{
  flake.tests.collection-in-identity = {
    test-plain-instance-reads-past-the-collection = {
      expr = plain.hosts.igloo.addr;
      expected = "10.0.1.1";
    };
    test-plain-instance-identity-is-demandable = {
      expr = builtins.isString plain.hosts.igloo.id_hash;
      expected = true;
    };
    test-plain-kind-identity-is-demandable = {
      expr = builtins.isString plain.schema.host.__mint.minted;
      expected = true;
    };
    test-plain-the-collection-holds-the-instance-value = {
      expr = map (a: a.domain) plain.schema.host.excludes;
      expected = [ "10.0.1.1" ];
    };
    # The collection reaches the instance's own `id_hash`: the instance's other reads serve.
    test-selfId-instance-reads-past-the-collection = {
      expr = (F.shapeTree "selfId").hosts.igloo.addr;
      expected = "10.0.1.1";
    };
    # A `computed` partial on the projection: the instance's other reads serve.
    test-partial-instance-reads-past-the-computed = {
      expr = F.partialTree.nodes.n1.addr;
      expected = "a1";
    };
    # The regime is unmoved: the guarded kind with no sealed component is minted.
    test-guarded-kind-is-minted = {
      expr = {
        identity = builtins.attrNames (F.identityOf (F.copyTree "GP" "none").schema.host);
        sealed = (F.copyTree "GP" "none").schema.host.__sealed;
      };
      expected = {
        identity = [ "minted" ];
        sealed = { };
      };
    };
  }
  # A copy of the identity cells imports: what the instance holds is computed from the content cells,
  # which the copy cannot alter, so the value is the honest one. Its identity reads are refused.
  // copyServes "U" "mint"
  // copyServes "UC" "mint"
  // copyServes "UC" "sealed"
  // copyServes "GC" "mint"
  // copyServes "GC" "sealed"
  // copyServes "GP" "mint"
  // {
    # the `{ }` is a change: `par` inherits `gpar`
    test-ancestors-copy-replaces-a-nonempty-map = {
      expr = builtins.attrNames (F.ancestorsCopyTree "inherits").schema.par.__kindAncestors != [ ];
      expected = true;
    };
    test-ancestors-copy-registry-instance-reads-the-honest-value = {
      expr = (F.ancestorsCopyTree "registry").hosts.igloo.addr;
      expected = "10.0.1.1";
    };
  }
  // ancestorsCopyComposes "inherits"
  // ancestorsCopyComposes "imports"
  // recomputeAgrees "U"
  // recomputeAgrees "UC"
  // recomputeAgrees "GC";
}
