{
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) mkInstanceRegistry mkInstanceType mkSchemaOption;
  M = genMerge;
  str =
    d:
    M.mkOption {
      type = M.types.str;
      default = d;
    };

  # den-hoag-2vo1m: THE KNOB. A kind read off the tree that declares the construct can be defined by
  # that tree's own config. The registry and its `mkInstanceType` sibling answer every shape the same.
  kindDecl = {
    options.schema = mkSchemaOption { };
    config.schema.host.options.addr = M.mkOption { type = M.types.str; };
  };
  inst.config.reg.h1.addr = "10.0.0.1";
  registry = { config, ... }: { options.reg = mkInstanceRegistry { } config.schema.host; };
  sibling =
    { config, ... }:
    {
      options.reg = M.mkOption {
        type = M.types.attrsOf (mkInstanceType { } config.schema.host);
        default = { };
      };
    };
  # Shape 1: a separate value-plane option decides the kind.
  knob = on: { config, ... }: {
    options.knob = M.mkOption {
      type = M.types.bool;
      default = on;
    };
    config.schema.host = if config.knob then { options.extra = str "x"; } else { };
  };
  # Shape 2: the construct's own instance NAMES decide its kind. The name set is the definitions', so
  # no kind is read to answer it.
  byNames = { config, ... }: {
    config.schema.host = if config.reg ? h1 then { options.extra = str "x"; } else { };
  };
  through =
    construct: extra:
    (M.evalModuleTree { } (
      [
        kindDecl
        construct
        inst
      ]
      ++ extra
    )).config.reg.h1;
  # The same through a `let` knot over the declaring evaluation.
  knotted =
    sib: extra:
    let
      e = M.evalModuleTree { } (
        [
          kindDecl
          {
            options.reg =
              if sib then
                M.mkOption {
                  type = M.types.attrsOf (mkInstanceType { } e.config.schema.host);
                  default = { };
                }
              else
                mkInstanceRegistry { } e.config.schema.host;
          }
          inst
        ]
        ++ extra
      );
    in
    e.config.reg.h1;
  read = h: [
    (builtins.attrNames h)
    (h.extra or null)
  ];
  both = f: [
    (read (f registry))
    (read (f sibling))
  ];
  withExtra = [
    [
      "_identity"
      "_identityKeys"
      "addr"
      "extra"
      "id_hash"
      "name"
    ]
    "x"
  ];
  withoutExtra = [
    [
      "_identity"
      "_identityKeys"
      "addr"
      "id_hash"
      "name"
    ]
    null
  ];
in
{
  flake.tests.instance-knob = {
    test-a-value-plane-knob-decides-both-constructs-alike = {
      expr = [
        (both (c: through c [ (knob false) ]))
        (both (c: through c [ (knob true) ]))
      ];
      expected = [
        [
          withoutExtra
          withoutExtra
        ]
        [
          withExtra
          withExtra
        ]
      ];
    };
    test-the-registrys-own-names-decide-its-kind-as-the-siblings-do = {
      expr = both (c: through c [ byNames ]);
      expected = [
        withExtra
        withExtra
      ];
    };
    test-the-registrys-own-names-decide-its-kind-through-a-knot = {
      expr = [
        (read (knotted false [ byNames ]))
        (read (knotted true [ byNames ]))
      ];
      expected = [
        withExtra
        withExtra
      ];
    };
  };
}
