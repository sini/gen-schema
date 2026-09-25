# (c+) — den-hoag-markof-partial-preimage-znfjq. A kind's mark is minted over its distinguishing
# CONTENT as per-component tags: every option-declaration attribute, each option's kind-level
# value, the declaration's `freeformType`, the collection values, `keySemantics`, `refs` and the
# computed fields. A component carrying a minted identity enters by it, an inert one whole, one
# with no value at WHNF as `undefined`, anything else as the sealed marker. Two declarations that then
# mint one mark and differ only at a sealed component are refused BY NAME by `kindEq`, never
# merged; every other pair is decided.
{
  genSchema,
  genMerge,
  genAlgebra,
  genIdentity,
  ...
}:
let
  inherit (genSchema) mkSchemaOption kindEq refinements;
  T = genMerge.types;
  kindIn =
    args: decl:
    (genMerge.evalModuleTree {
      modules = [
        { options.schema = mkSchemaOption args; }
        { config.schema.host = decl; }
      ];
    }).config.schema.host;
  kindOf = kindIn { };
  opt = type: genMerge.mkOption { inherit type; };
  decides = e: (builtins.tryEval e).success;

  portTcp = kindOf { options.port = opt (genSchema.refined T.int refinements.tcpPort); };
  portPos = kindOf { options.port = opt (genSchema.refined T.int refinements.positive); };
  fieldInt = kindOf { options.port = opt T.int; };
  fieldStr = kindOf { options.port = opt T.str; };

  # A predicate built from a REGISTERED constructor (ADR-0034's migration form).
  its = genAlgebra.mkIntensional genIdentity.hashIdentity {
    revision = "r1";
    members.between = a: v: v >= a.lo && v <= a.hi;
  };
  between = lo: hi: {
    check = its "between" { inherit lo hi; };
    message = "must be in [${toString lo}, ${toString hi}]";
  };
  portWide = kindOf { options.port = opt (genSchema.refined T.int (between 1 65535)); };
  portLow = kindOf { options.port = opt (genSchema.refined T.int (between 1 1023)); };

  # F1 · a METHOD BODY is content: the option it answers through is typed `str`, the body is a lambda.
  greeter =
    word:
    kindOf {
      options.name = opt T.str;
      methods.greeting = genSchema.schemaFn "g" T.str ({ name }: "${word} ${name}");
    };
  hello = greeter "Hello";
  bye = greeter "Bye";

  # F1's CLASS, the other members: content in a lambda the option plane cannot see into.
  withFqdn =
    suffix:
    kindOf {
      options.name = opt T.str;
      options.fqdn = opt T.str;
      imports = [ ({ config, ... }: { config.fqdn = "${config.name}.${suffix}"; }) ];
    };
  applied =
    f:
    kindOf {
      options.port = genMerge.mkOption {
        type = T.int;
        apply = f;
      };
    };
  lambdaDefault =
    f:
    kindOf {
      options.greet = genMerge.mkOption {
        type = T.raw;
        default = f;
      };
    };

  # F2 · inert content: a default, a kind-level definition, a collection value, a keySemantics value.
  defaulted =
    d:
    kindOf {
      options.port = genMerge.mkOption {
        type = T.int;
        default = d;
      };
    };
  defined = kindOf {
    options.port = genMerge.mkOption {
      type = T.int;
      default = 80;
    };
    config.port = 443;
  };
  parented =
    p:
    kindOf {
      options.name = opt T.str;
      parent = p;
    };
  categorised =
    c:
    kindIn {
      keySemantics.nixos.category = c;
    } { options.name = opt T.str; };
  # A default with content AND a throwing member: defined at WHNF, so sealed, never `undefined`.
  partial =
    a:
    kindOf {
      options.cfg = genMerge.mkOption {
        type = T.raw;
        default = {
          inherit a;
          b = throw "unset";
        };
      };
    };
  # A derivation default with a throwing passthru member (a package's shape, without nixpkgs).
  pkgDefault =
    n:
    kindOf {
      options.package = genMerge.mkOption {
        type = T.raw;
        default =
          (derivation {
            name = n;
            builder = "/bin/sh";
            system = "x86_64-linux";
          })
          // {
            passthru.broken = throw "meta";
          };
      };
    };
  # `freeformType` at both sites decides which undeclared instance keys are accepted.
  free =
    ft: kindOf ({ options.a = opt T.int; } // (if ft == null then { } else { freeformType = ft; }));
  moduleFree = kindOf {
    options.a = opt T.int;
    config._module.freeformType = T.attrsOf T.int;
  };
  described =
    d:
    kindOf {
      options.port = genMerge.mkOption {
        type = T.int;
        description = d;
      };
    };

  # F3 · the `mkType` arm (gen-aspects' door), where the published `options` is `{ }`.
  aspectShaped =
    { defs, kind, ... }:
    {
      __functor = _: _: { imports = map (d: d.value) defs; };
      inherit kind;
    };
  # A schema's own `mkType` body is content too: this one adds a definition the kind level
  # cannot evaluate (it reads an instance's `name`).
  fqdnShaped =
    suffix:
    { defs, kind, ... }:
    {
      __functor = _: _: {
        imports = map (d: d.value) defs ++ [
          ({ config, ... }: { config.fqdn = "${config.name}.${suffix}"; })
        ];
      };
      inherit kind;
    };
  fqdnKind =
    suffix:
    kindIn { mkType = fqdnShaped suffix; } {
      options.name = opt T.str;
      options.fqdn = opt T.str;
    };
  mkTypeKind =
    r: kindIn { mkType = aspectShaped; } { options.port = opt (genSchema.refined T.int r); };
in
{
  flake.tests.kind-mark-cplus = {
    # A MINTED field type enters by its digest, so kinds differing only in a field's type separate.
    test-a-minted-field-type-separates-the-mark = {
      expr = {
        marksDiffer = fieldInt.__mint.minted != fieldStr.__mint.minted;
        decided = kindEq fieldInt fieldStr;
      };
      expected = {
        marksDiffer = true;
        decided = false;
      };
    };
    # A SEALED field enters as the marker: the predicate-only pair shares a mark and is REFUSED.
    test-a-sealed-field-shares-the-mark-and-is-refused = {
      expr = {
        sameMark = portTcp.__mint.minted == portPos.__mint.minted;
        decided = decides (kindEq portTcp portPos);
      };
      expected = {
        sameMark = true;
        decided = false;
      };
    };
    # A REGISTERED predicate mints, so its field enters by digest and the pair separates, decided.
    test-a-registered-predicate-mints-and-separates = {
      expr = {
        marksDiffer = portWide.__mint.minted != portLow.__mint.minted;
        decided = kindEq portWide portLow;
        enforces = map (r: [
          (r.check 80)
          (r.check 8080)
        ]) (genSchema.refined T.int (between 1 1023)).__schema.refinements;
      };
      expected = {
        marksDiffer = true;
        decided = false;
        enforces = [
          [
            true
            false
          ]
        ];
      };
    };
    # F1 — two kinds differing only in a METHOD BODY are refused, never called one kind.
    test-a-method-body-is-sealed-content = {
      expr = {
        sameMark = hello.__mint.minted == bye.__mint.minted;
        decided = decides (kindEq hello bye);
        reflexive = kindEq hello hello;
      };
      expected = {
        sameMark = true;
        decided = false;
        reflexive = true;
      };
    };
    # F1's class: a function module's body, an `apply` and a lambda `default` are each sealed
    # content, so each pair shares a mark and is refused, never merged.
    test-lambda-content-is-sealed = {
      expr = {
        moduleBody = decides (kindEq (withFqdn "a") (withFqdn "b"));
        apply = decides (kindEq (applied (x: x)) (applied (x: x + 1)));
        lambdaDefault = decides (kindEq (lambdaDefault (x: "a")) (lambdaDefault (x: "b")));
        schemaMkType = decides (kindEq (fqdnKind "a") (fqdnKind "b"));
        moduleBodySameMark = (withFqdn "a").__mint.minted == (withFqdn "b").__mint.minted;
      };
      expected = {
        moduleBody = false;
        apply = false;
        lambdaDefault = false;
        schemaMkType = false;
        moduleBodySameMark = true;
      };
    };
    # F2 — inert content enters the mark: each pair separates and is decided `false`.
    test-inert-content-separates = {
      expr = {
        default = kindEq (defaulted 80) (defaulted 443);
        definition = kindEq (defaulted 80) defined;
        parent = kindEq (parented "net") (parented "site");
        category = kindEq (categorised "class") (categorised "channel");
      };
      expected = {
        default = false;
        definition = false;
        parent = false;
        category = false;
      };
    };
    # A presentation attribute is content: an instance module can read `options.port.description`.
    test-presentation-is-content = {
      expr = {
        marksDiffer = (described "one").__mint.minted != (described "two").__mint.minted;
        decided = kindEq (described "one") (described "two");
      };
      expected = {
        marksDiffer = true;
        decided = false;
      };
    };
    # A declaration's `freeformType`, at either site, is content: each pair differs in which
    # undeclared keys an instance accepts, and is decided two kinds.
    test-freeform-type-is-content = {
      expr = {
        topLevel = kindEq (free (T.attrsOf T.int)) (free null);
        moduleSite = kindEq moduleFree (free null);
        sealed = builtins.attrNames moduleFree.__sealed;
      };
      expected = {
        topLevel = false;
        moduleSite = false;
        sealed = [ "freeformType" ];
      };
    };
    # A value defined at WHNF with a throwing member keeps its content: a partial default and a
    # derivation default are sealed, so each pair shares a mark and is refused, never merged.
    test-partly-defined-content-is-sealed = {
      expr = {
        partialDefault = decides (kindEq (partial 1) (partial 2));
        derivationDefault = decides (kindEq (pkgDefault "hello") (pkgDefault "cowsay"));
        partialSealed = builtins.attrNames (partial 1).__sealed;
      };
      expected = {
        partialDefault = false;
        derivationDefault = false;
        partialSealed = [
          "options.cfg.default"
          "options.cfg.type"
          "value.cfg"
        ];
      };
    };
    # F3 — the `mkType` arm's mark and `kindEq` read ONE plane: its predicate-only pair is refused,
    # and a refined against a bare field separates.
    test-mktype-arm-reads-one-plane = {
      expr = {
        predicateOnly = decides (kindEq (mkTypeKind refinements.tcpPort) (mkTypeKind refinements.positive));
        refinedVsBare = kindEq (mkTypeKind refinements.tcpPort) (
          kindIn { mkType = aspectShaped; } { options.port = opt T.int; }
        );
      };
      expected = {
        predicateOnly = false;
        refinedVsBare = false;
      };
    };
    # F4 — a non-kind operand is refused by name, catchably.
    test-kindEq-refuses-a-non-kind-catchably = {
      expr = decides (kindEq { name = "not-a-kind"; } fieldInt);
      expected = false;
    };
    # Controls: a kind is one kind with itself; minted, inert and valueless twins are one kind
    # across evaluations; a field NAME separates.
    test-kindEq-decides-outside-the-collision = {
      expr = {
        reflexive = kindEq portTcp portTcp;
        nameDiffers = kindEq portTcp (kindOf {
          options.porte = opt (genSchema.refined T.int refinements.tcpPort);
        });
        mintedTwin = kindEq fieldInt (kindOf {
          options.port = opt T.int;
        });
        defaultTwin = kindEq (defaulted 80) (defaulted 80);
        requiredTwin = kindEq (kindOf { options.name = opt T.str; }) (kindOf {
          options.name = opt T.str;
        });
      };
      expected = {
        reflexive = true;
        nameDiffers = false;
        mintedTwin = true;
        defaultTwin = true;
        requiredTwin = true;
      };
    };
  };

  flake.testsError.kind-mark-cplus-refusal = {
    test-sealed-only-collision-refuses-by-name = {
      expr = kindEq portTcp portPos;
      expectedError = {
        type = "ThrownError";
        msg = "^gen-schema: kindEq: two declarations of 'host' mint one identity and differ, compared as values, only at sealed component\\(s\\) 'options.port.type'; a sealed component has no identity \\(ADR-0034\\): migrate it to a first-order term, a registered constructor over inert arguments, so that it mints$";
      };
    };
    test-method-body-collision-names-the-method = {
      expr = kindEq hello bye;
      expectedError = {
        type = "ThrownError";
        msg = "^gen-schema: kindEq: two declarations of 'host' mint one identity and differ, compared as values, only at sealed component\\(s\\) 'collections.methods.greeting'; .*$";
      };
    };
    test-partial-default-collision-names-its-components = {
      expr = kindEq (partial 1) (partial 2);
      expectedError = {
        type = "ThrownError";
        msg = "^gen-schema: kindEq: two declarations of 'host' mint one identity and differ, compared as values, only at sealed component\\(s\\) 'options.cfg.default', 'value.cfg'; .*$";
      };
    };
    test-derivation-default-collision-names-its-components = {
      expr = kindEq (pkgDefault "hello") (pkgDefault "cowsay");
      expectedError = {
        type = "ThrownError";
        msg = "^gen-schema: kindEq: two declarations of 'host' mint one identity and differ, compared as values, only at sealed component\\(s\\) 'options.package.default', 'value.package'; .*$";
      };
    };
    test-non-kind-operand-refuses-by-name = {
      expr = kindEq { name = "not-a-kind"; } fieldInt;
      expectedError = {
        type = "ThrownError";
        msg = "^gen-schema: kindEq: expected a kind value carrying a mint-backed mark \\(`__mint.minted`\\); got an attrset with no mark$";
      };
    };
  };
}
