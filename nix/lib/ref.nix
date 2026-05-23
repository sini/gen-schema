# schema.ref — dual-mode cross-instance references.
#
# Deferred: schema.ref "host" → marker type, bound via refs on mkInstanceRegistry
# Direct:   schema.ref config.fleet.hosts → resolved immediately
#
# Both modes accept string keys ("igloo") or instance values (config.fleet.hosts.igloo).
{ lib, ... }:
let
  # Resolved ref type with string/instance coercion.
  mkCoercingRefType =
    instances:
    lib.mkOptionType {
      name = "ref";
      description = "reference to an instance (key or value)";
      check = v: builtins.isString v || builtins.isAttrs v;
      merge =
        loc: defs:
        let
          val = lib.mergeOneOption loc defs;
        in
        if builtins.isString val then
          if instances ? ${val} then
            instances.${val}
          else
            throw "${lib.showOption loc}: reference '${val}' not found in instance registry"
        else
          val;
    };

  # Deferred ref — marker type carrying target kind name.
  # Unresolved: merge passes through the raw value (string or attrset).
  # mkInstanceRegistry detects .refKind and injects apply-based resolution.
  mkDeferredRef =
    kindName:
    lib.mkOptionType {
      name = "ref(${kindName})";
      description = "reference to a ${kindName} instance";
      check = v: builtins.isString v || builtins.isAttrs v;
      merge = loc: defs: lib.mergeOneOption loc defs;
    }
    // {
      refKind = kindName;
    };

  # Extract refKind from a type, traversing nullOr/listOf wrappers safely.
  # Returns the target kind name string, or null if not a ref type.
  # Recurse through nullOr/listOf wrappers to find the leaf refKind.
  getRefKind =
    type:
    if (type.refKind or null) != null then
      type.refKind
    else
      let
        et = (type.nestedTypes or { }).elemType or null;
      in
      if et != null then getRefKind et else null;

  # First-seen deduplication by id_hash. Shared by setOf (via mkCoerceChain) and toSet.
  # O(n) via groupBy + sort-by-index, preserving first-seen order.
  dedupByHash =
    vals:
    let
      indexed = lib.imap0 (
        i: v:
        if builtins.isAttrs v && v ? id_hash then
          {
            inherit i v;
            hash = v.id_hash;
          }
        else
          throw "gen-schema: dedupByHash: element missing id_hash — expected an instance"
      ) vals;
      grouped = builtins.groupBy (x: x.hash) indexed;
      firsts = lib.mapAttrsToList (_: xs: builtins.head xs) grouped;
      sorted = builtins.sort (a: b: a.i < b.i) firsts;
    in
    map (x: x.v) sorted;
in
{
  ref = target: if builtins.isString target then mkDeferredRef target else mkCoercingRefType target;

  inherit getRefKind dedupByHash;

  # Scan evaluated options for deferred ref types. Returns { fieldName = refKind; }.
  refsFromOptions =
    opts:
    let
      refFields = lib.filterAttrs (_: opt: (opt ? type) && (getRefKind opt.type) != null) opts;
    in
    lib.mapAttrs (_: opt: getRefKind opt.type) refFields;

  # Like refsFromOptions but preserves the option type for coercion chain construction.
  # Returns { fieldName = { refKind; type; }; }.
  refsFromOptionsWithTypes =
    opts:
    let
      refFields = lib.filterAttrs (_: opt: (opt ? type) && (getRefKind opt.type) != null) opts;
    in
    lib.mapAttrs (_: opt: {
      refKind = getRefKind opt.type;
      type = opt.type;
    }) refFields;

  # Set type: deduplicates by id_hash, preserving first-seen order.
  # Only meaningful with ref element types — setOf requires instance refs.
  # nestedTypes.elemType is set so getRefKind traverses through setOf like listOf.
  setOf =
    elemType:
    assert
      (getRefKind elemType != null)
      || throw "gen-schema: setOf: element type must be a ref type (e.g., setOf (ref \"host\")), got ${elemType.name or "unknown"}";
    let
      listType = lib.types.listOf elemType;
    in
    listType
    // {
      name = "setOf(${elemType.name})";
      description = "deduplicated set of ${elemType.description or elemType.name} (by id_hash)";
      isSetOf = true;
      # Do NOT set apply here — dedup must run AFTER ref coercion, which happens
      # in mkRefBindingModules' option-level apply. Type-level apply runs before
      # option apply, so strings wouldn't be resolved yet (no id_hash to dedup by).
      # Dedup is handled by mkCoerceChain's setOf branch in instance.nix instead.
      nestedTypes = { inherit elemType; };
    };

  # Convert a list of instances to a set with O(1) membership by id_hash.
  # Deduplicates by id_hash (first-seen wins), so safe to call on any instance list.
  toSet =
    instances:
    let
      deduped = dedupByHash instances;
      byHash = builtins.listToAttrs (
        map (i: {
          name = i.id_hash;
          value = i;
        }) deduped
      );
    in
    {
      member = # à la Data.Set.member
        x:
        if !(builtins.isAttrs x && x ? id_hash) then
          throw "gen-schema: toSet.member: expected an instance (with id_hash)"
        else
          byHash ? ${x.id_hash};
      toList = deduped;
      length = builtins.length deduped;
    };
}
