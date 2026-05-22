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
in
{
  ref = target: if builtins.isString target then mkDeferredRef target else mkCoercingRefType target;

  inherit getRefKind;

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
}
