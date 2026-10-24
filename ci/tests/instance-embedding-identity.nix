# A kind that declares an option typed by an instance type embeds that type's identity in its kind mark, and so
# in every entity `id_hash` of the kind (den-hoag-58bib β, N5 (ii)). The instance type states the base module
# arguments it refuses from a caller, the stated set enters the type's mint, so the mark and the ids of an
# embedding kind moved once at that landing; a kind embedding no instance type kept its ids. The three
# embedding shapes (direct, `attrsOf`, `mkInstanceRegistry`) and the control are read here against the digests
# they had before the set existed.
{
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) evalSchema mkInstanceType mkInstanceRegistry;
  T = genMerge.types;
  user =
    (evalSchema { } [ { config.schema.user.options.uname = genMerge.mkOption { type = T.str; }; } ])
    .user;
  kinds = evalSchema { } [
    {
      config.schema.host = {
        options.addr = genMerge.mkOption { type = T.str; };
        options.owner = genMerge.mkOption {
          type = mkInstanceType { } user;
          default.uname = "u";
        };
      };
      config.schema.farm = {
        options.addr = genMerge.mkOption { type = T.str; };
        options.users = genMerge.mkOption {
          type = T.attrsOf (mkInstanceType { } user);
          default = { };
        };
      };
      config.schema.site = {
        options.addr = genMerge.mkOption { type = T.str; };
        options.users = mkInstanceRegistry { } user;
      };
      config.schema.ctl.options.addr = genMerge.mkOption { type = T.str; };
    }
  ];
  idOf =
    k:
    (genMerge.evalModuleTree { } [
      {
        options.x = genMerge.mkOption {
          type = mkInstanceType { } k;
          default = { };
        };
        config.x.addr = "10.0.1.2";
      }
    ]).config.x.id_hash;
  read =
    builtins.mapAttrs
      (_: k: {
        mark = k.__mint.minted;
        id = idOf k;
      })
      {
        inherit (kinds)
          host
          farm
          site
          ctl
          ;
      };
  # before the instance type stated a set (gen-merge parity-sweep 39dde1e, gen-schema 0e14b56)
  before = {
    host = {
      mark = "schemakind:38618acfd494012a4f39d06111423effd8f6cb6bff5dced2a0cfd1985e42cde4";
      id = "host:4a16b56d3e592ce868b387a644523e928cc446f6eee673041d6a3d9041bd9673";
    };
    farm = {
      mark = "schemakind:e4c06d7bcd7e243138fd4fafc4405b463b6a5819926af53b745805b538a82197";
      id = "farm:ff1fd3297671d1e49541473ae68caa83d17518c84fba53bd5a76c16983bc2b11";
    };
    site = {
      mark = "schemakind:c681356b33a707d4daef883df091a097957b2fa3b8efbc1c8f6245bb02726a39";
      id = "site:5c282668c9f807858fd80454ae716be6fb1f2782bad636c2d8ed7516a8f927d6";
    };
    ctl = {
      mark = "schemakind:78b932f081142e7852c5468cb649839cf7c6b0001cf771f8fbd6eeb0dd65899d";
      id = "ctl:24388322fe7a1017f2902c374051def96a9d0cb7a6e21b856b66b0ce889fe6ed";
    };
  };
in
{
  flake.tests.instance-embedding-identity = {
    test-an-embedding-kind-moved-and-the-control-did-not = {
      expr = builtins.mapAttrs (n: r: {
        mark = r.mark != before.${n}.mark;
        id = r.id != before.${n}.id;
      }) read;
      expected = {
        host = {
          mark = true;
          id = true;
        };
        farm = {
          mark = true;
          id = true;
        };
        site = {
          mark = true;
          id = true;
        };
        ctl = {
          mark = false;
          id = false;
        };
      };
    };
    test-the-embedding-kinds-read-their-pinned-digests = {
      expr = read;
      expected = {
        host = {
          mark = "schemakind:5bbaf626e6c21baa1d6327d1563329e0373e4711ae498593114c861070915544";
          id = "host:b30f57cc0ba9f9f42cf57d3c3b2d05b8707c2d80e2b11d6b20cfd0d171ff36b6";
        };
        farm = {
          mark = "schemakind:870015c6d36e707977cc42aea452d0d26fc9f1b1a66467b6c35e40f064cd20e3";
          id = "farm:8a41f36ced3ad2c66434b8ae4e684820f8e01496e60d4978dc4f4d1eaf4528c7";
        };
        site = {
          mark = "schemakind:f0b1740f5a4b1d3ceda2893c909c07761a8c1db374d0e8c5d5ea241d2fe704df";
          id = "site:e08478092d78383c9bdaaed3df43f0d133fbb00b1d51a72d6fc3d9e669b79058";
        };
        inherit (before) ctl;
      };
    };
  };
}
