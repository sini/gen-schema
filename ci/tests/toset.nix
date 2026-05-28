{
  lib,
  schemaLib,
  ...
}:
let
  inherit (schemaLib)
    mkSchemaOption
    mkInstanceRegistry
    ref
    setOf
    toSet
    ;

  eval = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption { };
        options.hosts = mkInstanceRegistry eval.config.schema.host { };
        options.groups = mkInstanceRegistry eval.config.schema.group {
          refs.members = eval.config.hosts;
        };
        config.schema.host = {
          options.addr = lib.mkOption { type = lib.types.str; };
        };
        config.schema.group = {
          options.members = lib.mkOption {
            type = setOf (ref "host");
            default = [ ];
          };
        };
        config.hosts = {
          igloo = {
            addr = "10.0.1.1";
          };
          iceberg = {
            addr = "10.0.1.2";
          };
        };
        config.groups.web = {
          members = [
            "igloo"
            "iceberg"
          ];
        };
      }
    ];
  };

  members = eval.config.groups.web.members;
  set = toSet members;
  igloo = eval.config.hosts.igloo;
  iceberg = eval.config.hosts.iceberg;
in
{
  flake.tests.toset = {
    test-member-true = {
      expr = set.member igloo;
      expected = true;
    };
    test-member-false = {
      expr =
        let
          eval2 = lib.evalModules {
            modules = [
              {
                options.schema = mkSchemaOption { };
                options.hosts = mkInstanceRegistry eval2.config.schema.host { };
                config.schema.host.options.addr = lib.mkOption { type = lib.types.str; };
                config.hosts.other = {
                  addr = "10.0.1.3";
                };
              }
            ];
          };
        in
        set.member eval2.config.hosts.other;
      expected = false;
    };
    test-length = {
      expr = set.length;
      expected = 2;
    };
    test-toList-preserves-order = {
      expr = map (h: h.name) set.toList;
      expected = [
        "igloo"
        "iceberg"
      ];
    };
    test-dedup-on-raw-list = {
      # toSet deduplicates even if input wasn't from setOf
      expr =
        (toSet [
          igloo
          iceberg
          igloo
        ]).length;
      expected = 2;
    };
    test-dedup-first-seen = {
      expr =
        map (h: h.name)
          (toSet [
            igloo
            iceberg
            igloo
          ]).toList;
      expected = [
        "igloo"
        "iceberg"
      ];
    };
  };
}
