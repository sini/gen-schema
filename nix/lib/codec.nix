# Codec — serialize/deserialize kind instances.
#
# mkCodec builds per-field encoders/decoders from schema introspection.
# Built-in internals (name, id_hash) and collection keys (methods, validators,
# parent, kind, mixins, refinements) are excluded automatically. User-specified
# collection keys are also excluded. Remaining fields get identity transforms
# unless overridden via the fields spec.
{ lib, getRefKind }:
let
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
    {
      schema,
      kind,
      fields ? { },
      collections ? [ ],
    }:
    let
      meta = schema._kindMeta kind;
      kindResult = schema.${kind};

      methodNames = builtins.attrNames (kindResult.methods or { });
      allExcluded = builtinInternals ++ methodNames ++ builtinCollections ++ collections;

      resolvedFields = builtins.filter (n: !(builtins.elem n allExcluded)) meta.optionNames;

      # Validate fields spec — force evaluation to surface errors early
      _ = builtins.deepSeq (lib.mapAttrsToList (
        name: spec:
        if (spec.exclude or false) then
          null
        else if !(builtins.elem name resolvedFields) then
          throw "gen-schema: codec: field '${name}' in fields spec is not a declared option on kind '${kind}'"
        else
          null
      ) fields) null;

      # Walk a type tree to build ref encoder (mirrors mkCoerceChain in instance.nix)
      mkRefEncoder =
        type:
        if (type.refKind or null) != null then
          (v: v.name)
        else
          let
            et = (type.nestedTypes or { }).elemType or null;
          in
          if et == null then
            (v: v.name)
          else
            let
              inner = mkRefEncoder et;
            in
            if (type.name or "") == "nullOr" then
              (v: if v == null then null else inner v)
            else
              # listOf or setOf — map
              (v: map inner v);

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
          # Recursive: build sub-codec for nested submodule
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
              lib.foldl' (
                acc: n:
                let
                  subSpec = subFields.${n} or { };
                  encoder = if subSpec ? encode then subSpec.encode else (x: x);
                in
                if v ? ${n} then acc // { ${n} = encoder v.${n}; } else acc
              ) { } subFieldNames;
            decode =
              v:
              lib.foldl' (
                acc: n:
                let
                  subSpec = subFields.${n} or { };
                  decoder = if subSpec ? decode then subSpec.decode else (x: x);
                in
                if v ? ${n} then acc // { ${n} = decoder v.${n}; } else acc
              ) { } subFieldNames;
          }
        else
          # Check for ref type via schema introspection
          let
            opt = meta.options.${name} or null;
            refKind = if opt != null && opt ? type then getRefKind opt.type else null;
          in
          if refKind != null then
            {
              encode = mkRefEncoder opt.type;
              decode = v: v;
            }
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
        lib.foldl' (
          acc: name:
          let
            fc = fieldCodecs.${name};
          in
          if instance ? ${name} then acc // { ${name} = fc.encode instance.${name}; } else acc
        ) { } activeFields;

      decode =
        attrs:
        lib.foldl' (
          acc: name:
          let
            fc = fieldCodecs.${name};
          in
          if attrs ? ${name} then acc // { ${name} = fc.decode attrs.${name}; } else acc
        ) { } activeFields;

      encodeAll = registry: lib.mapAttrs (_: encode) registry;
      decodeAll = attrs: lib.mapAttrs (_: decode) attrs;

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
