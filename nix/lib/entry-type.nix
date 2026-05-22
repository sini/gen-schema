# Schema entry type and mkSchemaOption.
#
# A schema kind is a pure declaration — options, config, defaults, methods,
# and user-defined sidecar fields. Sidecars are extracted from defs before
# deferred module merge and exposed as attributes on the merged result.
# Computed fields are derived from extracted sidecars post-merge.
#
# Strict validation and identity hashing are instance-level concerns
# injected by mkInstanceType, not here.
{
  lib,
  mkMethodsModule,
  refsFromOptions,
}:
let
  mkSchemaEntryType =
    {
      baseModule ? null,
      sidecars ? { },
      computed ? null,
    }:
    let
      base = lib.types.deferredModule;

      # methods is a built-in sidecar — user sidecars are additional
      allSidecars =
        let
          merged = {
            methods = {
              default = { };
            };
            validators = {
              default = [ ];
            };
          }
          // sidecars;
        in
        if merged ? __functor then
          throw "sidecar '__functor' is reserved — cannot be used as a sidecar key"
        else if merged ? kind then
          throw "sidecar 'kind' is reserved — cannot be used as a sidecar key"
        else
          merged;

      # Infer merge strategy from default type
      inferMerge =
        name: sidecar:
        if sidecar ? merge then
          sidecar.merge
        else if builtins.isList sidecar.default then
          (acc: val: acc ++ val)
        else if builtins.isAttrs sidecar.default then
          (acc: val: acc // val)
        else
          throw "sidecar '${name}': no merge strategy — default is not a list or attrset; provide an explicit merge function";

      sidecarKeys = lib.attrNames allSidecars;
    in
    base
    // {
      merge =
        loc: defs:
        let
          kind = lib.last loc;

          # Extract each sidecar from defs, merge with strategy.
          # NOTE: sidecars must be declared via inline attrsets, not path modules.
          # Path-based kind declarations pass through as paths — the isAttrs check
          # skips them. If two modules declare the same sidecar key, they merge
          # according to the sidecar's merge strategy.
          extractedSidecars = lib.mapAttrs (
            name: sidecar:
            let
              merge = inferMerge name sidecar;
            in
            lib.foldl' (
              acc: d: if builtins.isAttrs d.value && d.value ? ${name} then merge acc d.value.${name} else acc
            ) sidecar.default defs
          ) allSidecars;

          # Computed fields from extracted sidecars + raw defs
          # kind (lib.last loc) is passed so computed can produce entry-specific fields
          computedFields = if computed != null then computed extractedSidecars defs else { };

          # Strip all sidecar keys before deferredModule merge
          strippedDefs = map (
            d:
            if builtins.isAttrs d.value && lib.any (k: d.value ? ${k}) sidecarKeys then
              d // { value = builtins.removeAttrs d.value sidecarKeys; }
            else
              d
          ) defs;

          # Inject baseModule + methods module (methods is the only sidecar
          # that generates instance-level options via mkMethodsModule)
          injected =
            lib.optional (baseModule != null) {
              file = "gen-schema/base";
              value = if builtins.isFunction baseModule then baseModule kind else baseModule;
            }
            ++ lib.optional (extractedSidecars.methods != { }) {
              file = "gen-schema/methods";
              value = mkMethodsModule kind extractedSidecars.methods;
            };

          merged = base.merge loc (strippedDefs ++ injected);
        in
        # Precedence: computed overrides sidecars of the same name.
        # __functor is reserved — sidecars/computed must not use it as a key.
        {
          __functor =
            _:
            { ... }:
            {
              imports = [ merged ];
            };
          inherit kind;
        }
        // extractedSidecars
        // computedFields;
    };

  mkSchemaOption =
    {
      strict ? true,
      baseModule ? null,
      sidecars ? { },
      computed ? null,
    }:
    lib.mkOption {
      description = "Schema — typed record registry with extension points";
      default = { };
      type = lib.types.submodule (
        { config, ... }:
        {
          freeformType = lib.types.lazyAttrsOf (mkSchemaEntryType {
            inherit baseModule sidecars computed;
          });

          # Schema-level strict setting — stored for mkInstanceType to read
          options._strict = lib.mkOption {
            internal = true;
            type = lib.types.bool;
            default = strict;
          };

          options._topology = lib.mkOption {
            internal = true;
            type = lib.types.attrsOf (
              lib.types.submodule {
                options.children = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [ ];
                  description = "Child kind names nested inside this kind.";
                };
              }
            );
            default = { };
            description = "Declared parent-child nesting between kinds.";
          };

          options._meta = lib.mkOption {
            readOnly = true;
            internal = true;
            type = lib.types.submodule {
              options.kindNames = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                description = "All kind names in the schema";
              };
              options.kindMeta = lib.mkOption {
                type = lib.types.functionTo lib.types.raw;
                description = "Per-kind introspection: options, types, identity keys, refs";
              };
              options.topology = lib.mkOption {
                type = lib.types.raw;
                description = "Parent-child nesting: { kind = { parent, children }; }";
              };
              options.refEdges = lib.mkOption {
                type = lib.types.listOf lib.types.raw;
                description = "All ref edges: [ { from, field, to } ]";
              };
              options.edges = lib.mkOption {
                type = lib.types.listOf lib.types.raw;
                description = "Unified edge view: parent (Neron P) + ref (Neron I) edges";
              };
              options.roots = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                description = "Kinds with no parent in the topology";
              };
              options.leaves = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                description = "Kinds with no children in the topology";
              };
            };
          };
          config._meta =
            let
              kindNames = lib.sort (a: b: a < b) (lib.filter (n: !(lib.hasPrefix "_" n)) (lib.attrNames config));

              kindMeta =
                k:
                if !(config ? ${k}) then
                  throw "kindMeta: '${k}' is not a declared schema kind"
                else
                  let
                    dummy = lib.evalModules { modules = [ config.${k} ]; };
                  in
                  {
                    optionNames = lib.attrNames dummy.options;
                    inherit (dummy) options;
                    refs = refsFromOptions dummy.options;
                  };

              # Derive topology: combine declared _topology with inverse parent pointers.
              # Validates: no undeclared kinds, no multiple parents.
              topology =
                let
                  declared = config._topology;
                  allDeclaredChildren = lib.concatMap (pk: declared.${pk}.children) (lib.attrNames declared);

                  # Validate: all topology keys and children must be declared kinds
                  unknownParents = lib.filter (k: !(builtins.elem k kindNames)) (lib.attrNames declared);
                  unknownChildren = lib.filter (k: !(builtins.elem k kindNames)) allDeclaredChildren;
                  _ =
                    if unknownParents != [ ] then
                      throw "gen-schema: _topology references undeclared kind '${builtins.head unknownParents}'"
                    else if unknownChildren != [ ] then
                      throw "gen-schema: _topology.*.children references undeclared kind '${builtins.head unknownChildren}'"
                    else
                      null;

                  # Build parent map, detecting multiple parents
                  parentMap = lib.foldl' (
                    acc: parentKind:
                    lib.foldl' (
                      a: child:
                      if a ? ${child} then
                        throw "gen-schema: kind '${child}' has multiple parents ('${a.${child}}' and '${parentKind}') in _topology"
                      else
                        a // { ${child} = parentKind; }
                    ) acc declared.${parentKind}.children
                  ) { } (lib.attrNames declared);
                in
                builtins.seq _ (
                  builtins.seq parentMap (
                    lib.genAttrs kindNames (k: {
                      parent = parentMap.${k} or null;
                      children = (declared.${k} or { }).children or [ ];
                    })
                  )
                );

              # Materialize all ref edges from kindMeta.refs across all kinds
              refEdges = lib.concatMap (
                fromKind:
                let
                  refs = (kindMeta fromKind).refs;
                in
                lib.mapAttrsToList (field: toKind: {
                  from = fromKind;
                  inherit field;
                  to = toKind;
                }) refs
              ) kindNames;
              # Unified edge view: Neron P (parent) + I (ref/import) edges
              parentEdges = lib.concatMap (
                k:
                let
                  t = topology.${k};
                in
                lib.optional (t.parent != null) {
                  from = k;
                  to = t.parent;
                  type = "parent";
                  field = null;
                }
              ) kindNames;

              edges = parentEdges ++ map (e: e // { type = "ref"; }) refEdges;

              roots = builtins.filter (k: topology.${k}.parent == null) kindNames;
              leaves = builtins.filter (k: topology.${k}.children == [ ]) kindNames;
            in
            {
              inherit
                kindNames
                kindMeta
                topology
                refEdges
                edges
                roots
                leaves
                ;
            };
        }
      );
    };
in
{
  inherit mkSchemaEntryType mkSchemaOption;
}
