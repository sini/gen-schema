# Refinement contracts (§ Findler 2002, co-location from § Rondon 2008).
# Predicate metadata stored in __schema attr on gen-merge/gen-types types.
{ merge }:
let
  normalizeRefinements = r: if builtins.isList r then r else [ r ];

  # A refined type is DERIVED from its base rather than described from scratch: it keeps the
  # base's value behaviour and adds the predicate metadata. That derivation still has to go
  # through the completion path. `baseType // { __schema = …; }` is an override over an already
  # completed type, and every field the override does not name still answers for the BASE —
  # including the two that rebuild it, `functor.type` (what typeMerge returns when an option is
  # declared twice) and `substSubModules`. Either path hands back the bare base with __schema
  # gone and the refinements silently unenforced, which is the fail-open answer this construction
  # exists to prevent. Re-completing WITHOUT the base's functor and typeMerge is what breaks the
  # inheritance: the supplied functor below is the one mkOptionType derives typeMerge from, so the
  # merge relation stays gen-merge's own rather than a copy of it living here.
  #
  # The FUNCTOR carries the distinguishing name; the type keeps the base's. They are separate
  # axes: `name` is the value vocabulary a refined int still speaks in its error messages, while
  # the functor name is the identity two declarations are compared on. Distinguishing only the
  # latter makes the refusal fail CLOSED — two declarations of the same refined type merge to it
  # with refinements intact, while a refined and an unrefined declaration of the same option are
  # "not mergeable", a stated conflict rather than a silent drop to the unrefined type.
  mkRefinedType =
    baseType: refinements:
    let
      normalized = normalizeRefinements refinements;
      result = merge.mkOptionType (
        builtins.removeAttrs baseType [
          "functor"
          "typeMerge"
        ]
        // {
          __schema = {
            refinements = normalized;
            baseType = baseType;
          };
          # payload null is the honest shape for a metadata decoration: there is nothing to fold
          # when two of these meet, only an identity to agree on. A base whose own functor carries
          # a payload does not lose it — a refined type and its base never merge in the first place.
          functor = {
            name = "refined<${baseType.name or "?"}>";
            type = result;
            payload = null;
            binOp = _a: _b: null;
          };
          # A base that carries no module set answers null to a substitution, and so does a
          # refinement of it — refining null would be a type where the base refused to give one.
          substSubModules =
            m:
            let
              substituted = if baseType ? substSubModules then baseType.substSubModules m else null;
            in
            if substituted == null then null else mkRefinedType substituted normalized;
        }
      );
    in
    result;

  getRefinements = type: if type ? __schema then type.__schema.refinements else [ ];

  isRefined = type: type ? __schema && type.__schema ? refinements;

  checkRefinements =
    fieldPath: type: value:
    let
      refs = getRefinements type;
    in
    builtins.filter (r: r != null) (
      builtins.map (
        r:
        if r.check value then
          null
        else
          {
            field = fieldPath;
            message = r.message;
            inherit value;
            lazy = r.lazy or false;
          }
      ) refs
    );

  refinements = {
    tcpPort = {
      check = self: self > 0 && self < 65536;
      message = "must be a valid TCP port (1-65535)";
    };
    nonEmpty = {
      check = self: self != "";
      message = "must not be empty";
    };
    positive = {
      check = self: self > 0;
      message = "must be positive";
    };
  };
in
{
  inherit
    mkRefinedType
    getRefinements
    isRefined
    checkRefinements
    refinements
    ;
  types.refined = mkRefinedType;
}
