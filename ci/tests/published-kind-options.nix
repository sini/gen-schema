# A KIND'S PUBLISHED `options` RECORDS, READ THROUGH THIS REPOSITORY'S OWN LOCK. The kind introspection reads
# gen-merge's declaration stratum (`declaredOptions`), so what a kind publishes as `options` is that door's records,
# and a gen-merge whose door drops an untyped declaration's `type` or refuses a `default` that reads the kind's own
# `config` turns these reads into an abort and a refusal on every consumer (den-hoag-options-checked-wrapper-mly8e,
# K-X2). The records must read as the value path serves them: an untyped declaration's type is `unspecified`, and a
# `default` reading `config` is served.
#
# The cells read the gen-merge this ci flake locks; `test-the-published-lock-pins-the-gen-merge-the-cells-read`
# holds the root lock (the one a consumer of gen-schema gets) to the same revision, so a passing suite speaks for
# the published surface. RED at 1e4bc83, whose two locks pin gen-merge a0bb51f (before den-hoag-qqywn's door):
# `untyped-has-type` false, `untyped-type-name` "<absent>", `config-reading-default` "<error>".
{
  genSchema,
  genMerge,
  ...
}:
let
  T = genMerge.types;
  schema =
    (genMerge.evalModuleTree { } [
      { options.schema = genSchema.mkSchemaOption { }; }
      { config.schema.k.options.x = genMerge.mkOption { default = 1; }; }
      {
        config.schema.c =
          { config, ... }:
          {
            options.z = genMerge.mkOption {
              type = T.int;
              default = 1;
            };
            options.y = genMerge.mkOption {
              type = T.int;
              default = config.z + 1;
            };
          };
      }
    ]).config.schema;
  x = schema.k.options.x;
  y = schema.c.options.y;
  # A refusal reads `<error>`; an absent attribute is tested with `?` first, so no read here aborts the suite.
  try =
    v:
    let
      r = builtins.tryEval (builtins.deepSeq v v);
    in
    if r.success then r.value else "<error>";
  lockedRev = file: (builtins.fromJSON (builtins.readFile file)).nodes.gen-merge.locked.rev;
in
{
  flake.tests.published-kind-options = {
    # positive control: a typed declaration reads on every gen-merge
    test-typed-type-name = {
      expr = try schema.c.options.z.type.name;
      expected = "int";
    };
    test-untyped-has-type = {
      expr = try (x ? type);
      expected = true;
    };
    test-untyped-type-name = {
      expr = try (if x ? type then x.type.name else "<absent>");
      expected = "unspecified";
    };
    test-untyped-default = {
      expr = try x.default;
      expected = 1;
    };
    test-config-reading-has-default = {
      expr = try (y ? default);
      expected = true;
    };
    test-config-reading-default = {
      expr = try y.default;
      expected = 2;
    };
    test-config-reading-type-name = {
      expr = try y.type.name;
      expected = "int";
    };
    test-untyped-names = {
      expr = try (builtins.attrNames schema.k.options);
      expected = [ "x" ];
    };
    test-the-published-lock-pins-the-gen-merge-the-cells-read = {
      expr = lockedRev ../../flake.lock;
      expected = lockedRev ../flake.lock;
    };
  };
}
