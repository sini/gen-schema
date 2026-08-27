{ prelude }:
let
  escapeMd = s: builtins.replaceStrings [ "|" "`" "[" "]" "*" ] [ "\\|" "\\`" "\\[" "\\]" "\\*" ] s;
in
{
  renderDocs =
    schema:
    let
      kinds = schema._kindNames;
      renderKind =
        kind:
        let
          opts = schema.${kind}.options;
          # `internal` is the shared per-option marker (also read by id-hash.nix's
          # isPrimitiveOption) for a derived option — includes methods, which mkCodec
          # already excludes from serialized shape on the same flag. No name-prefix
          # heuristic here: a user field is never dropped from docs just for being
          # named with a leading underscore, only for actually being marked internal.
          userOpts = prelude.filter (n: n != "id_hash" && !(opts.${n}.internal or false)) (
            builtins.attrNames opts
          );
        in
        prelude.concatStringsSep "\n" (
          [
            "## ${kind}"
            ""
            "| Option | Type | Default | Description |"
            "|--------|------|---------|-------------|"
          ]
          ++ map (renderOption opts) userOpts
        );
      renderOption =
        options: name:
        let
          opt = options.${name};
          defaultStr =
            if opt ? defaultText then
              if builtins.isAttrs opt.defaultText then opt.defaultText.text or "—" else toString opt.defaultText
            else if opt ? default then
              let
                d = builtins.tryEval (builtins.deepSeq opt.default opt.default);
                fmt =
                  v:
                  if builtins.isBool v then
                    (if v then "true" else "false")
                  else if builtins.isList v then
                    "[ ... ]"
                  else
                    toString v;
              in
              if d.success then fmt d.value else "—"
            else
              "—";
        in
        "| ${escapeMd name} | ${escapeMd (opt.type.name or "?")} | ${escapeMd defaultStr} | ${
          escapeMd (opt.description or "")
        } |";
    in
    prelude.concatMapStringsSep "\n\n" renderKind kinds;
}
