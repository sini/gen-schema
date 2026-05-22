# Bridge from gen-schema topology to scope-engine graph inputs.
#
# Converts schema metadata (_meta.topology, _meta.edges) and evaluated
# instance registries into the { parentGraph, importGraph, decls, types }
# structure that scope-engine.buildNodes expects.
#
# Two modes:
#   buildKindGraph schema        — kind-level graph (kinds as nodes)
#   buildInstanceGraph schema fleet — instance-level graph (instances as nodes)
{ lib }:
let
  # Kind-level graph: each kind is a node, topology provides P edges,
  # ref declarations provide I edges. No instances needed.
  # Useful for schema introspection and static analysis.
  buildKindGraph =
    schema:
    let
      meta = schema._meta;
      inherit (meta) kindNames topology edges;

      # Parent edges from topology: child → parent
      parentEdges = lib.concatMap (
        k:
        let
          t = topology.${k};
        in
        lib.optional (t.parent != null) {
          from = k;
          to = t.parent;
        }
      ) kindNames;

      # Ref edges from schema declarations: fromKind → toKind
      refEdges = builtins.filter (e: e.type == "ref") edges;
      importEdges = map (e: {
        inherit (e) from to;
      }) refEdges;
    in
    {
      parentGraph = {
        vertices = kindNames;
        edges = parentEdges;
      };
      importGraph = {
        vertices = [ ];
        edges = importEdges;
      };
      decls = lib.genAttrs kindNames (k: {
        kind = k;
        inherit (topology.${k}) parent children;
        refs = lib.listToAttrs (
          map (e: {
            name = e.field;
            value = e.to;
          }) (builtins.filter (e: e.from == k) refEdges)
        );
      });
      types = lib.genAttrs kindNames (_: "kind");
    };

  # Instance-level graph: each instance is a node (kind:name format).
  # Parent edges connect child instances to their parent instances.
  # Ref edges connect instances via resolved references.
  #
  # fleet: { kindName → { instanceName → instanceConfig } }
  # Each instance must have .nodeId (injected by mkInstanceType).
  buildInstanceGraph =
    schema: fleet:
    let
      meta = schema._meta;
      inherit (meta) kindNames topology;
      refEdges = builtins.filter (e: e.type == "ref") meta.edges;

      # All instance node IDs
      allNodeIds = lib.concatMap (
        kind: map (name: "${kind}:${name}") (builtins.attrNames (fleet.${kind} or { }))
      ) kindNames;

      # Parent edges: for each child kind instance, connect to parent instance.
      # This requires the consumer to provide a resolver that maps
      # (childKind, childName) → parentName. The convention is:
      # if childKind has a parent kind, the child instance lives nested
      # inside the parent and we can derive the mapping from fleet structure.
      #
      # For flat registries (not nested), parentEdges are omitted.
      # Consumers can provide explicit parent mappings via parentResolver.
      parentEdges = lib.concatMap (
        childKind:
        let
          parentKind = topology.${childKind}.parent or null;
        in
        if parentKind == null then
          [ ]
        else
          lib.concatMap (
            parentName:
            let
              parentInstance = (fleet.${parentKind} or { }).${parentName} or null;
              # If parent instance has nested children of this kind, extract them.
              childInstances = builtins.attrNames (
                if parentInstance != null && parentInstance ? ${childKind} then
                  parentInstance.${childKind}
                else
                  # Fallback: check if fleet has this kind at top level
                  fleet.${childKind} or { }
              );
            in
            map (childName: {
              from = "${childKind}:${childName}";
              to = "${parentKind}:${parentName}";
            }) childInstances
          ) (builtins.attrNames (fleet.${parentKind} or { }))
      ) kindNames;

      # Import edges from resolved ref fields.
      # For each instance with a ref field, if the ref resolves to another instance,
      # create an import edge.
      importEdges = lib.concatMap (
        refEdge:
        let
          fromKind = refEdge.from;
          inherit (refEdge) field;
          toKind = refEdge.to;
        in
        lib.concatMap (
          fromName:
          let
            inst = (fleet.${fromKind} or { }).${fromName} or null;
            refValue = if inst != null then inst.${field} or null else null;
            # Ref resolves to an instance — extract its name
            toName =
              if refValue == null then
                null
              else if builtins.isString refValue then
                refValue
              else
                refValue.name or null;
          in
          lib.optional (toName != null) {
            from = "${fromKind}:${fromName}";
            to = "${toKind}:${toName}";
          }
        ) (builtins.attrNames (fleet.${fromKind} or { }))
      ) refEdges;

      # Declarations: instance config data per node
      decls = lib.listToAttrs (
        lib.concatMap (
          kind:
          lib.mapAttrsToList (name: inst: {
            name = "${kind}:${name}";
            value = inst;
          }) (fleet.${kind} or { })
        ) kindNames
      );

      # Types: kind name per node
      types = lib.listToAttrs (
        lib.concatMap (
          kind:
          map (name: {
            name = "${kind}:${name}";
            value = kind;
          }) (builtins.attrNames (fleet.${kind} or { }))
        ) kindNames
      );
    in
    {
      parentGraph = {
        vertices = allNodeIds;
        edges = parentEdges;
      };
      importGraph = {
        vertices = [ ];
        edges = importEdges;
      };
      inherit decls types;
    };
in
{
  inherit buildKindGraph buildInstanceGraph;
}
