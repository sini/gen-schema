{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) mkSchemaOption mkInstanceRegistry kindEq;

  # den-hoag-ux9xg: a kind's collection holds a value that reads an instance the kind types. Declared
  # `identity = false`, the collection is outside the kind's identity, so importing the kind into
  # `igloo` reads none of it, as nixpkgs' twin (a submodule beside a list option) never does. Three
  # shapes, one per read that took the contents through the mark: `plain` (the import's completion
  # stamp), `inheriting` (the module key of a kind with a parent) and `parentHolds` (the PARENT's
  # collection reaches the instance, and the child names the parent by value: `formOf`).
  # The undeclared twin is the guard's, in `tests-process.nix` (`collection-identity-guard`): it aborts.
  excludes = {
    default = [ ];
    merge = acc: val: acc ++ val;
    identity = false;
  };
  # `extra` is the rest of the schema's construction: `{ }`, or a `computed` that exposes the declared
  # collection (C1: a computed field is minted over the declaration with that collection taken out).
  exposing.computed = c: _: { excluded = c.excludes; };
  evalWith = evalWithSchema { };
  evalWithSchema =
    extra: shape:
    genMerge.evalModuleTree { } [
      (
        { config, ... }:
        {
          options.schema = mkSchemaOption ({ collections.excludes = excludes; } // extra);
          options.hosts = mkInstanceRegistry { } config.schema.host;
          options.aspects = genMerge.mkOption { type = genMerge.types.attrsOf genMerge.types.anything; };
          config.schema.conf = lib.optionalAttrs (shape == "parentHolds") {
            excludes = [ config.aspects.unwanted ];
          };
          config.schema.host =
            lib.optionalAttrs (shape != "plain") { inherits = [ config.schema.conf ]; }
            // {
              options.addr = genMerge.mkOption { type = genMerge.types.str; };
            }
            // lib.optionalAttrs (shape != "parentHolds") { excludes = [ config.aspects.unwanted ]; };
          config.hosts.igloo.addr = "10.0.1.1";
          config.aspects.unwanted.domain = config.hosts.igloo.addr;
        }
      )
    ];
  holder = shape: e: if shape == "parentHolds" then e.config.schema.conf else e.config.schema.host;
  cellsOf = cellsWith "" { };
  cellsWith =
    tag: extra: shape:
    let
      e = evalWithSchema extra shape;
    in
    {
      "test-${shape}${tag}-instance-reads-past-the-collection" = {
        expr = e.config.hosts.igloo.addr;
        expected = "10.0.1.1";
      };
      "test-${shape}${tag}-instance-identity-is-demandable" = {
        expr = builtins.isString e.config.hosts.igloo.id_hash;
        expected = true;
      };
      "test-${shape}${tag}-kind-identity-is-demandable" = {
        expr = builtins.isString e.config.schema.host.__mint.minted;
        expected = true;
      };
      "test-${shape}${tag}-the-collection-holds-the-instance-value" = {
        expr = map (a: a.domain) (holder shape e).excludes;
        expected = [ "10.0.1.1" ];
      };
    };

  # Two trees, one `host` each, differing only in the collection's contents. Declared, the two are one
  # kind (the quotient the declaration states); undeclared, two. Each kind value keeps its own data.
  hostIn = hostInWith { };
  hostInWith =
    extra: spec: v:
    (genMerge.evalModuleTree { } [
      {
        options.schema = mkSchemaOption ({ collections.excludes = spec; } // extra);
        config.schema.host = {
          options.addr = genMerge.mkOption { type = genMerge.types.str; };
          excludes = [ v ];
        };
      }
    ]).config.schema.host;
  undeclared = removeAttrs excludes [ "identity" ];
in
{
  flake.tests.collection-identity-false =
    cellsOf "plain"
    // cellsOf "inheriting"
    // cellsOf "parentHolds"
    // cellsWith "-computed" exposing "plain"
    // cellsWith "-computed" exposing "inheriting"
    // cellsWith "-computed" exposing "parentHolds"
    // {
      # The quotient and the data, in one oracle (red where the pair is two kinds, red on a build that
      # hands one kind the other's data).
      test-declared-pair-is-one-kind-and-keeps-each-kinds-data = {
        expr = {
          oneKind = kindEq (hostIn excludes "x") (hostIn excludes "y");
          data = [
            (hostIn excludes "x").excludes
            (hostIn excludes "y").excludes
          ];
        };
        expected = {
          oneKind = true;
          data = [
            [ "x" ]
            [ "y" ]
          ];
        };
      };
      # A computed field over the declared collection enters the identity through the projection: the
      # pair is one kind, and each kind value keeps the field as computed.
      test-declared-computed-pair-is-one-kind-and-keeps-each-field = {
        expr = {
          oneKind = kindEq (hostInWith exposing excludes "x") (hostInWith exposing excludes "y");
          fields = [
            (hostInWith exposing excludes "x").excluded
            (hostInWith exposing excludes "y").excluded
          ];
        };
        expected = {
          oneKind = true;
          fields = [
            [ "x" ]
            [ "y" ]
          ];
        };
      };
      # the live control: undeclared, the computed pair is two kinds
      test-undeclared-computed-pair-is-two-kinds = {
        expr = kindEq (hostInWith exposing undeclared "x") (hostInWith exposing undeclared "y");
        expected = false;
      };
      test-declared-pair-is-one-kind = {
        expr = kindEq (hostIn excludes "x") (hostIn excludes "y");
        expected = true;
      };
      # a control, green at the base library too: the pair's data, without the quotient
      test-declared-pair-keeps-each-kinds-data = {
        expr = [
          (hostIn excludes "x").excludes
          (hostIn excludes "y").excludes
        ];
        expected = [
          [ "x" ]
          [ "y" ]
        ];
      };
      # the live control: the same pair, undeclared, is two kinds
      test-undeclared-pair-is-two-kinds = {
        expr = kindEq (hostIn undeclared "x") (hostIn undeclared "y");
        expected = false;
      };
    };
}
