{ lib }:
{
  renderDocs =
    schema:
    let
      kinds = schema._meta.kindNames;
      renderKind =
        kind:
        let
          meta = schema._meta.kindMeta kind;
          userOpts = builtins.filter (n: !(lib.hasPrefix "_" n) && n != "id_hash") meta.optionNames;
        in
        ''
          ## ${kind}

          | Option | Type | Default | Description |
          |--------|------|---------|-------------|
          ${lib.concatMapStringsSep "\n" (renderOption meta.options) userOpts}'';
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
        "| ${name} | ${opt.type.name or "?"} | ${defaultStr} | ${opt.description or ""} |";
    in
    lib.concatMapStringsSep "\n\n" renderKind kinds;
}
