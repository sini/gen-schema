# schema.ref — dual-mode cross-instance references.
#
# Deferred: schema.ref "host" → marker type, bound via refs on mkInstanceRegistry
# Direct:   schema.ref config.fleet.hosts → resolved immediately
#
# Both modes accept string keys ("igloo") or instance values (config.fleet.hosts.igloo).
{ lib, mkRefType }:
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
    // { refKind = kindName; };

  # Extract refKind from a type, traversing nullOr/listOf wrappers safely.
  # Returns the target kind name string, or null if not a ref type.
  getRefKind =
    type:
    if (type.refKind or null) != null then
      type.refKind
    else
      let
        et = ((type.nestedTypes or { }).elemType or null);
      in
      if et != null then (et.refKind or null) else null;
in
{
  ref =
    target:
    if builtins.isString target then mkDeferredRef target else mkCoercingRefType target;

  inherit getRefKind;
}
