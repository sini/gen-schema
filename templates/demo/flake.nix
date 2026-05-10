{
  inputs = {
    den-schema.url = "github:denful/den-schema";
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
  };

  outputs =
    { den-schema, nixpkgs, ... }:
    let
      lib = nixpkgs.lib;
      schemaLib = den-schema.lib;
      inherit (schemaLib) mkSchema;

      eval = lib.evalModules {
        specialArgs = { inherit schemaLib; };
        modules = [
          # Schema: declare kinds (host, user) and their options
          {
            options.schema = mkSchema {
              baseModule = {
                options.description = lib.mkOption {
                  type = lib.types.str;
                  default = "";
                  description = "Human-readable description (shared base).";
                };
              };
            };
            config.schema.host = ./schema/host.nix;
            config.schema.user = ./schema/user.nix;
            config.schema.service = ./schema/service.nix;
          }
          # Fleet: declare instances
          ./fleet.nix
        ];
      };

      cfg = eval.config;
    in
    {
      # Summary attribute exercising all Phase 1 features:
      #   kinds, instances, strict validation, id_hash, shared base, default propagation
      fleet = {
        # Instance registry keys
        hostNames = builtins.attrNames cfg.hosts;
        userNames = builtins.attrNames cfg.users;

        # Field values from instances
        iglooAddr = cfg.hosts.igloo.addr;
        iglooRole = cfg.hosts.igloo.role;

        # Default propagation: igloo.system was not set, should be x86_64-linux
        iglooSystem = cfg.hosts.igloo.system;

        # Override: iceberg explicitly set aarch64-linux
        icebergSystem = cfg.hosts.iceberg.system;

        # User fields
        tuxShell = cfg.users.tux.shell;

        # Default propagation: yeti.shell was not set, should be /bin/bash
        yetiShell = cfg.users.yeti.shell;

        # Shared base option (description) on host kind
        iglooDescription = cfg.hosts.igloo.description;

        # Identity hash: deterministic sha256 of kind + primitive fields
        iglooHash = cfg.hosts.igloo.id_hash;

        # Cross-instance references: service.host resolves to the full host instance
        serviceNames = builtins.attrNames cfg.services;
        nginxHost = cfg.services.nginx.host.name;
        nginxHostAddr = cfg.services.nginx.host.addr;
        postgresHost = cfg.services.postgres.host.name;
      };
    };
}
