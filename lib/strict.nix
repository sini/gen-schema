# mkStrictModule — closed-world instance schemas.
#
# Sets a kind's `_module.freeformType` to a type whose merge always throws, so
# any key not declared as an option is rejected with a fix suggestion. This turns
# the module system's open (freeform) default into a closed record for instances
# that opt into `strict` (see instance.nix).
#
# WHERE THE BLAMED NAME COMES FROM. A freeform type is merged at its LEVEL, not at a key: the
# engine calls `merge prefix defs`, nixpkgs' raw `freeformType.merge` protocol, with `prefix` the
# instance's own location and each def's value rooted at that level. So `path` never names a key
# (its last segment is the instance, and at a root evaluation it is `[ ]`), and the key lives only
# in the values. It is read back against this level's own `options` tree: a name is part of a
# capture path's ancestry exactly when the tree declares it as a GROUP, and the first name the tree
# does not declare IS the key — the engine's own capture rule, applied to the tree it descended.
# Keys undeclared inside a submodule nested under the kind are captured at that submodule's level,
# not this one, and are refused there.
#
# Relocated from gen-algebra/module so gen-schema owns its full module-system
# surface; gen-algebra is the pure algebra root.
{
  prelude,
  merge,
  constructionRelation,
  isOptionDecl,
}:
let
  # unmatchedPaths : options -> value -> [ [ name ] ] — every capture path in `v` under `opts`.
  unmatchedPaths =
    opts: v:
    builtins.concatMap (
      n:
      let
        o = opts.${n} or null;
      in
      if o == null then
        [ [ n ] ]
      else if !(isOptionDecl o) && builtins.isAttrs v.${n} then
        map (p: [ n ] ++ p) (unmatchedPaths o v.${n})
      else
        [ ]
    ) (builtins.attrNames v);

  # A path rendered as Nix SOURCE, so the printed remedy parses and declares the key it names. Each
  # segment follows nixpkgs' `showOption`/`escapeNixIdentifier` rule: bare when it is an identifier
  # and not a keyword, else a string literal — `renderValue`'s JSON string with `$` escaped, which
  # is nixpkgs' `escapeNixString`. `merge.showOption` joins with `.` and quotes nothing, so a key
  # holding a dot would print as a nested path and the remedy would declare the wrong option.
  keywords = [
    "assert"
    "else"
    "if"
    "in"
    "inherit"
    "let"
    "or"
    "rec"
    "then"
    "with"
  ];
  renderSegment =
    s:
    if builtins.match "[a-zA-Z_][a-zA-Z0-9_'-]*" s != null && !(builtins.elem s keywords) then
      s
    else
      builtins.replaceStrings [ "$" ] [ "\\$" ] (prelude.renderValue s);
  renderPath = p: builtins.concatStringsSep "." (map renderSegment p);
in
{
  mkStrictModule =
    kind:
    { options, ... }:
    {
      # gen-merge reads `_module` only from `config` (top-level `_module` is dropped as
      # non-config on a structured module), so this must live under `config`.
      #
      # Built on every evaluation of this module, so a module imported twice meets a second record:
      # `constructionRelation` merges the two when they are strict for one kind.
      config._module.freeformType = merge.mkDefault (
        let
          self = merge.mkOptionType {
            name = "strict";
            functor = constructionRelation "strict" { minted.kind = kind; } self;
            merge =
              path: decls:
              let
                walked = prelude.unique (builtins.concatMap (d: unmatchedPaths options d.value) decls);
                # Capture always leaves a path, so the walk is empty only if it and the engine
                # disagree; the refusal then names the defs' top-level names rather than nothing.
                keys =
                  if walked != [ ] then
                    walked
                  else
                    prelude.unique (
                      builtins.concatMap (
                        d: if builtins.isAttrs d.value then map (n: [ n ]) (builtins.attrNames d.value) else [ ]
                      ) decls
                    );
                files = prelude.unique (map (d: d.file) decls);
                shown =
                  if keys == [ ] then
                    "a definition"
                  else
                    builtins.concatStringsSep ", " (map (k: "\"${renderPath k}\"") keys);
                verb = if builtins.length keys > 1 then "are" else "is";
                at = if path == [ ] then "" else "instance at ${merge.showOption path}, ";
              in
              throw (
                "STRICT MODE: ${shown} ${verb} not declared on ${kind} (${at}defined in ${builtins.concatStringsSep ", " files})."
                + builtins.concatStringsSep "" (
                  map (k: "\nFix: schema.${kind}.options.${renderPath k} = mkOption { ... };") keys
                )
              );
          };
        in
        self
      );
    };
}
