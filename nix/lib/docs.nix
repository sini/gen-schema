{ lib }:
let
  escapeMd = s: builtins.replaceStrings [ "|" ] [ "\\|" ] s;
in
{
  renderDocs =
    schema:
    let
      kinds = schema._meta.kindNames;
      renderKind =
        kind:
        let
          meta = schema._meta.kindMeta kind;
          userOpts = lib.filter (n: !(lib.hasPrefix "_" n) && n != "id_hash") meta.optionNames;
        in
        lib.concatStringsSep "\n" (
          [
            "## ${kind}"
            ""
            "| Option | Type | Default | Description |"
            "|--------|------|---------|-------------|"
          ]
          ++ map (renderOption meta.options) userOpts
        );
      renderOption =
        options: name:
        let
          opt = options.${name};
          defaultStr =
            if opt ? defaultText then
              if builtins.isAttrs opt.defaultText then opt.defaultText.text or "—" else toString opt.defaultText
            else
              "—";
        in
        "| ${escapeMd name} | ${escapeMd (opt.type.name or "?")} | ${escapeMd defaultStr} | ${escapeMd (opt.description or "")} |";
    in
    lib.concatMapStringsSep "\n\n" renderKind kinds;
}
