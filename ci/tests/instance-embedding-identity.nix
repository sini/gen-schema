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
    # re-pinned when the instance type came to mint over its construction, so each kind reads the
    # embedded kind's mark (den-hoag-dwln8); the control is unmoved
    test-the-embedding-kinds-read-their-pinned-digests = {
      expr = read;
      expected = {
        host = {
          mark = "schemakind:addf2cef43e79d5398311bc1adc314f45b703bb8c0fd6fac9d41b752dbbf2bb4";
          id = "host:fc31f5c0f4fdaa0265a9b3a6a9ed3437e7b623b8a1eda34282ec8f7ed09dd120";
        };
        farm = {
          mark = "schemakind:573c97354d2bdd02d1d8f72730c5d77bf25bfb7153fa70962bfb9d50cb688e59";
          id = "farm:e127c49753c985690b3285bacae029397097a05c27e6c2252795da9d95e9d463";
        };
        site = {
          mark = "schemakind:9e4a3887578f67c238980cd18f86fea23cb0c2785e40480879d3cbcdc286b217";
          id = "site:e6f7726a5c3c10352b3dd62c62cac769c21114c5670e097ccf82fa3bd51b08cf";
        };
        inherit (before) ctl;
      };
    };
  };
}
