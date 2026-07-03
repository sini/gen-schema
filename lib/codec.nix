# Codec — serialize/deserialize kind instances.
#
# mkCodec builds per-field encoders/decoders from schema introspection.
# Built-in internals (name, id_hash) and collection keys (methods, validators,
# parent, kind, mixins, refinements) are excluded automatically. Additional
# fields can be excluded via excludeFields. Remaining fields get identity
# transforms unless overridden via the fields spec or types registry.
{ prelude }:
let
  # Does value v structurally inhabit type t? Used ONLY for codec either/oneOf branch
  # selection. nixpkgs `t.check` was `v -> bool`, but the gen stack splits this: gen-types
  # leaf checkers expose `verify` (v -> null|err) with a CURRIED `check`, while gen-merge
  # structural types (listOf/attrsOf/submodule) carry no scalar predicate at all — so a raw
  # `t.check v` no longer discriminates. This walks the structural shape instead.
  inhabits =
    t: v:
    let
      tn = t.name or "";
    in
    if t ? verify then
      t.verify v == null
    else if tn == "listOf" then
      builtins.isList v
    else if tn == "attrsOf" || tn == "lazyAttrsOf" || tn == "submodule" then
      builtins.isAttrs v
    else if tn == "nullOr" then
      (
        let
          et = (t.nestedTypes or { }).elemType or null;
        in
        v == null || (et != null && inhabits et v)
      )
    else if tn == "either" then
      (
        let
          l = (t.nestedTypes or { }).left or null;
          r = (t.nestedTypes or { }).right or null;
        in
        (l != null && inhabits l v) || (r != null && inhabits r v)
      )
    else if t ? check then
      t.check v
    else
      true;

  builtinCollections = [
    "methods"
    "validators"
    "parent"
    "kind"
    "mixins"
    "refinements"
  ];
  builtinInternals = [
    "name"
    "id_hash"
  ];

  json = {
    encode = builtins.toJSON;
    decode = builtins.fromJSON;
  };

  mkCodec =
    kindValue:
    {
      fields ? { },
      types ? { },
      excludeFields ? [ ],
    }:
    assert
      (kindValue ? kind && kindValue ? options)
      || throw "gen-schema: mkCodec: expected a kind value (e.g., schema.host), got an attrset without 'kind' or 'options'";
    let
      kind = kindValue.kind;
      kindOptions = kindValue.options;

      methodNames = builtins.attrNames (kindValue.methods or { });
      allExcluded = builtinInternals ++ methodNames ++ builtinCollections ++ excludeFields;

      resolvedFields = builtins.filter (n: !(builtins.elem n allExcluded)) (
        builtins.attrNames kindOptions
      );

      # Validate fields spec — force evaluation to surface errors early
      _ = builtins.deepSeq (prelude.mapAttrsToList (
        name: spec:
        if (spec.exclude or false) then
          null
        else if !(builtins.elem name resolvedFields) then
          throw "gen-schema: codec: field '${name}' in fields spec is not a declared option on kind '${kind}'"
        else
          null
      ) fields) null;

      # Walk a type tree to build encoder/decoder.
      # Handles: ref auto-detect, type-registered codecs, wrapper traversal.
      mkTypeEncoder =
        name: type:
        let
          typeName = type.name or "";
          et = (type.nestedTypes or { }).elemType or null;
        in
        # Ref leaf — always takes priority
        if (type.refKind or null) != null then
          {
            encode = v: v.name;
            decode = v: v;
          }
        # Type-registered codec — direct match
        else if types ? ${typeName} then
          {
            encode = types.${typeName}.encode;
            decode = types.${typeName}.decode or (v: v);
          }
        # nullOr wrapper — recurse into elemType
        else if typeName == "nullOr" && et != null then
          let
            inner = mkTypeEncoder name et;
          in
          {
            encode = v: if v == null then null else inner.encode v;
            decode = v: if v == null then null else inner.decode v;
          }
        # listOf wrapper — map over elemType
        else if typeName == "listOf" && et != null then
          let
            inner = mkTypeEncoder name et;
          in
          {
            encode = v: map inner.encode v;
            decode = v: map inner.decode v;
          }
        # attrsOf wrapper — mapAttrs over elemType
        else if typeName == "attrsOf" && et != null then
          let
            inner = mkTypeEncoder name et;
          in
          {
            encode = v: prelude.mapAttrs (_: inner.encode) v;
            decode = v: prelude.mapAttrs (_: inner.decode) v;
          }
        # setOf wrapper — map (setOf is a list at value level)
        else if (type.isSetOf or false) && et != null then
          let
            inner = mkTypeEncoder name et;
          in
          {
            encode = v: map inner.encode v;
            decode = v: map inner.decode v;
          }
        # either / oneOf — check-based dispatch, left-biased
        else if typeName == "either" then
          let
            left = (type.nestedTypes or { }).left or null;
            right = (type.nestedTypes or { }).right or null;
            leftCodec = if left != null then mkTypeEncoder name left else null;
            rightCodec = if right != null then mkTypeEncoder name right else null;
          in
          {
            encode =
              v:
              if left != null && inhabits left v then
                leftCodec.encode v
              else if right != null && inhabits right v then
                rightCodec.encode v
              else
                throw "gen-schema: codec: no matching branch for either/oneOf on field '${name}'";
            decode =
              v:
              if left != null && inhabits left v then
                leftCodec.decode v
              else if right != null && inhabits right v then
                rightCodec.decode v
              else
                v; # decode is lenient
          }
        # No match — identity
        else
          {
            encode = v: v;
            decode = v: v;
          };

      mkFieldCodec =
        name:
        let
          spec = fields.${name} or { };
        in
        if spec ? exclude && spec.exclude then
          null
        else if spec ? encode then
          {
            encode = spec.encode;
            decode = spec.decode or (v: v);
          }
        else if spec ? fields then
          # Recursive: build sub-codec for nested submodule.
          # NOTE: ref auto-detection is NOT applied to sub-fields — only custom
          # encode/decode and exclude. If a sub-field is a ref, provide an explicit encoder.
          let
            subFields = spec.fields;
            subFieldNames = builtins.filter (
              n:
              let
                s = subFields.${n} or { };
              in
              !(s.exclude or false)
            ) (builtins.attrNames subFields);
          in
          {
            encode =
              v:
              prelude.foldl' (
                acc: n:
                let
                  subSpec = subFields.${n} or { };
                  encoder = if subSpec ? encode then subSpec.encode else (x: x);
                in
                if v ? ${n} then acc // { ${n} = encoder v.${n}; } else acc
              ) { } subFieldNames;
            decode =
              v:
              prelude.foldl' (
                acc: n:
                let
                  subSpec = subFields.${n} or { };
                  decoder = if subSpec ? decode then subSpec.decode else (x: x);
                in
                if v ? ${n} then acc // { ${n} = decoder v.${n}; } else acc
              ) { } subFieldNames;
          }
        else
          # Walk the type tree for ref auto-detect, type-registered codecs, and wrappers
          let
            opt = kindOptions.${name} or null;
          in
          if opt != null && opt ? type then
            mkTypeEncoder name opt.type
          else
            {
              encode = v: v;
              decode = v: v;
            };

      fieldCodecs = builtins.listToAttrs (
        builtins.concatMap (
          name:
          let
            fc = mkFieldCodec name;
          in
          if fc == null then
            [ ]
          else
            [
              {
                inherit name;
                value = fc;
              }
            ]
        ) resolvedFields
      );

      activeFields = builtins.attrNames fieldCodecs;

      encode =
        instance:
        prelude.foldl' (
          acc: name:
          let
            fc = fieldCodecs.${name};
          in
          if instance ? ${name} then acc // { ${name} = fc.encode instance.${name}; } else acc
        ) { } activeFields;

      decode =
        attrs:
        prelude.foldl' (
          acc: name:
          let
            fc = fieldCodecs.${name};
          in
          if attrs ? ${name} then acc // { ${name} = fc.decode attrs.${name}; } else acc
        ) { } activeFields;

      encodeAll = registry: prelude.mapAttrs (_: encode) registry;
      decodeAll = attrs: prelude.mapAttrs (_: decode) attrs;

      serialize = fmt: instance: fmt.encode (encode instance);
      deserialize = fmt: raw: decode (fmt.decode raw);
      serializeAll = fmt: registry: fmt.encode (encodeAll registry);
      deserializeAll = fmt: raw: decodeAll (fmt.decode raw);
    in
    builtins.seq _ {
      inherit
        encode
        decode
        encodeAll
        decodeAll
        serialize
        deserialize
        serializeAll
        deserializeAll
        ;
      json = {
        serialize = serialize json;
        deserialize = deserialize json;
        serializeAll = serializeAll json;
        deserializeAll = deserializeAll json;
      };
    };
in
{
  inherit mkCodec;
}
