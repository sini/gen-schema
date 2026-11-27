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
      mark = "schemakind:3f5b55373a1a2b2d7bf0e7d48cb70a9ca8c2029b1c28db33a283607ba937c057";
      id = "ctl:8a14574ebb5fce5b8a03633a1b9d0d320794a261aa3510bd415d9a229d038158";
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
          mark = "schemakind:6143a1a8ea1262e81a557456e2e48ec45ff6e95cbed9ff255b86865f760c3c11";
          id = "host:6e386c2559937cebc7f05e196b69ef9803284f5a0b772a55f0a81ae299a35a04";
        };
        farm = {
          mark = "schemakind:7c5ec2de20adc54d11d675eab9247b7f68c8082051ccc118ce3210ecc79a4f4e";
          id = "farm:29073a8e2164b9e6e2470497116b3322129b2796f4321b35cea8c36f7a5b1d1a";
        };
        site = {
          mark = "schemakind:1b2980f5b267e09ccde172d15c1aaf4bc284c5114ee849a152d623a79a1dd6fb";
          id = "site:ffd8cff68b0f7050bbe181c4b0af58ee569993077e1abd80c214c674f0800c0e";
        };
        inherit (before) ctl;
      };
    };
  };
}
