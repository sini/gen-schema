# A non-strict instance's freeform (`attrsOf anything`, lib/instance.nix) carries a DERIVATION WHOLE when it is
# defined once, and refuses it defined twice or beside an attrset, as the nixpkgs twin (a submodule whose
# freeform is nixpkgs' `attrsOf anything`) does (den-hoag-z9m0f). The arm is gen-merge's `anything`
# (`stringCoercibleSet`); this cell pins that the instance freeform reaches it, which is den's path.
#
# RED at a gen-merge without the arm: the function-carrying derivation is rebuilt per key (`whole` false on
# Nix and Determinate; Lix compares a rebuilt closure equal), a throwing `outPath` throws at the key set, and
# the two refusal cells are served (a per-key union).
{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) evalSchema mkSchemaOption mkInstanceRegistry;
  schema = evalSchema { schemaOption = mkSchemaOption { strict = false; }; } [
    { config.schema.host.options.name = genMerge.mkOption { type = genMerge.types.str; }; }
  ];
  drv = derivation {
    name = "zg-schema-p";
    # a literal: nix-unit evaluates purely
    system = "x86_64-linux";
    builder = "/bin/sh";
  };
  # function-carrying: `==` on a rebuilt closure is false on Nix and Determinate
  pf = drv // {
    g = x: x + 1;
  };
  pt = drv // {
    outPath = throw "zg-schema-outpath";
  };
  gen =
    defs:
    (genMerge.evalModuleTree { } (
      [
        { options.hosts = mkInstanceRegistry { } schema.host; }
        { config.hosts.h.name = "h"; }
      ]
      ++ map (d: { config.hosts.h.pkg = d; }) defs
    )).config.hosts.h.pkg;
  nixpkgs =
    defs:
    (lib.evalModules {
      modules = [
        {
          options.hosts = lib.mkOption {
            type = lib.types.attrsOf (
              lib.types.submodule {
                freeformType = lib.types.attrsOf lib.types.anything;
                options.name = lib.mkOption { type = lib.types.str; };
              }
            );
          };
        }
        { config.hosts.h.name = "h"; }
      ]
      ++ map (d: { config.hosts.h.pkg = d; }) defs;
    }).config.hosts.h.pkg;
  both = defs: read: {
    gen = read (gen defs);
    nixpkgs = read (nixpkgs defs);
  };
  ok = x: (builtins.tryEval (builtins.seq x true)).success;
  alike = want: {
    gen = want;
    nixpkgs = want;
  };
in
{
  flake.tests.instance-freeform-string-coercible = {
    test-a-derivation-defined-once-is-carried-whole = {
      expr = both [ pf ] (v: {
        whole = removeAttrs v [ "type" ] == removeAttrs pf [ "type" ];
        drvPath = v.drvPath == drv.drvPath;
      });
      expected = alike {
        whole = true;
        drvPath = true;
      };
    };
    test-a-throwing-outpath-defined-once-reads-its-names = {
      expr = both [ pt ] (v: {
        names = builtins.attrNames v;
        outPath = ok v.outPath;
      });
      expected = alike {
        names = builtins.attrNames pt;
        outPath = false;
      };
    };
    test-a-derivation-defined-twice-is-refused = {
      expr = both [
        drv
        drv
      ] ok;
      expected = alike false;
    };
    test-a-derivation-beside-an-attrset-is-refused = {
      expr = both [
        drv
        { extra = 1; }
      ] ok;
      expected = alike false;
    };
    # LIVE CONTROL, unmoved: two plain attrsets still merge per key
    test-control-two-attrsets-merge = {
      expr = both [
        { a = 1; }
        { b = 2; }
      ] (v: v);
      expected = alike {
        a = 1;
        b = 2;
      };
    };
  };
}
