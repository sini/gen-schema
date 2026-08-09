# Field refs — inert, identity-bearing references to a FIELD of another instance.
#
# A field ref is plain data (no functions, no thunk wrappers): a record containing field refs stays
# fully introspectable, and the cross-instance dependency graph is computable before any resolution
# (Mokhov, Mitchell & Peyton Jones, *Build Systems à la Carte*, ICFP 2018, §3 — static/applicative
# task dependencies, known before any value is produced, not dynamic/monadic ones).
#
# ── KINSHIP with `ref` (./ref.nix), the other reference vocabulary in this library ──
#
# The two are not variants of one construct; they sit on opposite sides of the type/value axis:
#
#   `ref`       — an option TYPE on a field, DECLARING that the field points at an instance of some
#                 kind. Lives in the kind's schema. Derives kind -> kind edges (`_refEdges`).
#   `fieldRef`  — a VALUE inhabiting such a position, NAMING which instance, and which field of it.
#                 Lives in a default or a contributed value. Derives (instance, field) ->
#                 (instance, field) edges, from the values a scan finds.
#
# So the type declares that a dependence exists and the value says what it is; and neither DECLARES
# the dependence FACT — both derive it from structure that is present for another reason. Their
# refusals differ accordingly: `ref` refuses an unresolvable key at merge time, `fieldRef` refuses a
# non-identity target at application time.
{ prelude }:
let
  inherit (builtins)
    isAttrs
    isList
    isFunction
    all
    isString
    attrNames
    concatLists
    concatStringsSep
    map
    ;
  inherit (prelude) imap0;

  fieldRefMarker = "__genSchemaFieldRef";

  isFieldRef = v: isAttrs v && (v.${fieldRefMarker} or false) == true;

  # Scan position, for the refusal's blame. [ ] is the scanned value itself.
  renderAt =
    at: if at == [ ] then "(the scanned value itself)" else concatStringsSep "." (map toString at);
in
{
  inherit fieldRefMarker isFieldRef;

  # fieldRef instance path -> field ref record
  #   `instance` MUST carry id_hash: routing is by identity, and a display key is not one, so a
  #   name string never crosses the boundary. Identity in ≡ identity out — the record carries the
  #   given entry, so the scan hands back the caller's own instance rather than a lookup of it.
  fieldRef =
    aspect: path:
    if !(isAttrs aspect && aspect ? id_hash) then
      throw "gen-schema: fieldRef: target must be an instance carrying id_hash, never a name string"
    else if !(isList path && path != [ ] && all isString path) then
      throw "gen-schema: fieldRef: path must be a non-empty list of field-name strings"
    else
      {
        ${fieldRefMarker} = true;
        inherit aspect path;
      };

  # fieldRefsIn v -> [ { at; aspect; path; } ] — deep structural scan.
  #   `at` is the subpath within v where the ref sits ([ ] = v itself); attrset keys and list
  #   indices compose it. Refs are inspected as records, never resolved. The scan is structurally
  #   strict: detecting a ref forces its position to WHNF, since Nix has no primitive that inspects
  #   a thunk without forcing it.
  #
  #   TOTAL ON ITS DOMAIN, AND THAT DOMAIN EXCLUDES FUNCTIONS. A function found in a scanned
  #   position is REFUSED by name, never treated as a leaf. Three grounds, and they compound:
  #
  #     1. A ref inside a closure is unreachable to ANY structural scan — Nix exposes no primitive
  #        that inspects a function body — so treating one as a leaf fails OPEN: the edge is
  #        missing, the cycle it would have closed goes undetected, and the unresolved ref record
  #        then leaks into consumer output AS DATA. Silent bad data, not a missed diagnostic.
  #     2. The values this scan is applied to are declared data. A schema of `{ default; merge }`
  #        leaves holds nothing parametric — only class *content* is a function, and it *consumes*
  #        resolved settings rather than containing refs — so on contract-conforming input the
  #        refusal is a no-op and observes nothing.
  #     3. Refusing ELIMINATES the underivable case rather than declaring it unanalysable. Every
  #        dependence fact that survives the scan is then a derived one, which is the totality
  #        Mokhov's static extraction has by typing: the inexpressible case is refused, not
  #        silently admitted. An assertion that a fact is unanalysable is not a proof of it.
  fieldRefsIn =
    v:
    let
      go =
        at: val:
        if isFieldRef val then
          [
            {
              inherit at;
              inherit (val) aspect path;
            }
          ]
        else if isAttrs val then
          concatLists (map (k: go (at ++ [ k ]) val.${k}) (attrNames val))
        else if isList val then
          concatLists (imap0 (i: e: go (at ++ [ i ]) e) val)
        else if isFunction val then
          throw "gen-schema: fieldRefsIn: function at scanned position ${renderAt at} — this scan's domain is data and excludes functions, because a field ref inside a closure is unreachable to a structural scan; make the position data, or keep it out of the scanned structure"
        else
          [ ];
    in
    go [ ] v;
}
