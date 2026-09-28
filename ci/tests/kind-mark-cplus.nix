# (c+) — den-hoag-markof-partial-preimage-znfjq. A kind's mark is minted over its distinguishing
# CONTENT as per-component tags: each option declaration's `type` and no other attribute of it
# (den-hoag-pa887, arm A), the declaration's `freeformType`, the collection values, `keySemantics`,
# `refs`, the computed fields and the opaque modules; an option's kind-level value is not a
# component. A component carrying a minted identity enters by it, an inert
# one whole, one with no value at WHNF as `undefined`, anything else as the sealed marker. Two
# declarations that then mint one mark and differ only at a sealed component are refused BY NAME by
# `kindEq`, never merged; every other pair is decided.
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
  # One option declaration differing at one attribute other than `type`.
  attributed =
    attr: v:
    kindOf {
      options.port = genMerge.mkOption (
        {
          type = T.int;
        }
        // {
          ${attr} = v;
        }
      );
    };
  # Two kinds differing only at `attr` (`a` against `b`): `true` is the reopened collision.
  sharesIdentity =
    attr: a: b:
    kindEq (attributed attr a) (attributed attr b);

  # den-hoag-pa887 · THE ORDINARY IDIOM: a function module whose option attribute, or kind-level
  # definition, reads an instance's `name`, which the kind does NOT declare (`name` is injected per
  # instance). At kind level the read aborts UNCATCHABLY, so a kind identity demanded over it takes
  # the whole evaluation down; the cell below is green only if the mark never forces it.
  readsName =
    attr: word:
    kindOf {
      imports = [
        (
          { config, ... }:
          {
            options.p = genMerge.mkOption (
              {
                type = T.str;
                default = "x";
              }
              // {
                ${attr} = "${word}-${config.name}";
              }
            );
          }
        )
      ];
    };
  definesName =
    wrap: word:
    kindOf {
      imports = [
        (
          { config, ... }:
          {
            options.p = genMerge.mkOption { type = T.str; };
            config.p = wrap "${word}-${config.name}";
          }
        )
      ];
    };
  instanceP =
    kind:
    (genMerge.evalModuleTree {
      modules = [
        { options.hosts = genSchema.mkInstanceRegistry kind { }; }
        { config.hosts.a = { }; }
      ];
    }).config.hosts.a;

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
    # F1's class: a function module's body and a schema's `mkType` are each sealed content, so each
    # pair shares a mark and is refused, never merged.
    test-lambda-content-is-sealed = {
      expr = {
        moduleBody = decides (kindEq (withFqdn "a") (withFqdn "b"));
        schemaMkType = decides (kindEq (fqdnKind "a") (fqdnKind "b"));
        moduleBodySameMark = (withFqdn "a").__mint.minted == (withFqdn "b").__mint.minted;
      };
      expected = {
        moduleBody = false;
        schemaMkType = false;
        moduleBodySameMark = true;
      };
    };
    # F2 — inert content outside the option declarations enters the mark: each pair separates and
    # is decided `false`.
    test-inert-content-separates = {
      expr = {
        parent = kindEq (parented "net") (parented "site");
        category = kindEq (categorised "class") (categorised "channel");
      };
      expected = {
        parent = false;
        category = false;
      };
    };
    # ★ THE REOPENED COLLISIONS, PINNED — den-hoag-pa887 arm A, bounded, accepted by the owner until
    # arm C lands. An option enters the mark by its `type` alone, and its kind-level value not at
    # all, so two kinds differing ONLY at another attribute of a declaration are ONE kind. One cell
    # per class, each stating its collision so it is never silent. pa887's arm C (by constructor:
    # an option declared in an attrset module is inert and re-enters the mark) is the fix, and it
    # flips every `true` below: rewrite each cell then, never widen it.
    #
    # F2 (the znfjq gate's pair): an inert literal default, 80 against 443, shares one mark.
    test-f2-reopened-inert-default-shares-identity-until-pa887-c = {
      expr = {
        default = sharesIdentity "default" 80 443;
        sameMark = (attributed "default" 80).__mint.minted == (attributed "default" 443).__mint.minted;
      };
      expected = {
        default = true;
        sameMark = true;
      };
    };
    # F2's definition member: a kind-level definition (`config.port = 443`) is not a component.
    test-f2-reopened-kind-level-definition-shares-identity-until-pa887-c = {
      expr = kindEq (attributed "default" 80) defined;
      expected = true;
    };
    # Was sealed and REFUSED by name (F1 and the partly-defined class): a lambda, a partial and a
    # derivation default are no longer components, so each pair is one kind, silently.
    test-f1-reopened-non-inert-default-shares-identity-until-pa887-c = {
      expr = {
        lambdaDefault = kindEq (lambdaDefault (x: "a")) (lambdaDefault (x: "b"));
        partialDefault = kindEq (partial 1) (partial 2);
        partialSealed = builtins.attrNames (partial 1).__sealed;
        derivationDefault = kindEq (pkgDefault "hello") (pkgDefault "cowsay");
      };
      expected = {
        lambdaDefault = true;
        partialDefault = true;
        partialSealed = [ "options.cfg.type" ];
        derivationDefault = true;
      };
    };
    # Was sealed and REFUSED by name (F1): an `apply` is no longer a component.
    test-f1-reopened-apply-shares-identity-until-pa887-c = {
      expr = sharesIdentity "apply" (x: x) (x: x + 1);
      expected = true;
    };
    # N3's presentation keys: an instance module can read `options.port.description`, yet a pair
    # differing there is one kind.
    test-n3-reopened-presentation-shares-identity-until-pa887-c = {
      expr = {
        description = sharesIdentity "description" "one" "two";
        example = sharesIdentity "example" 1 2;
        defaultText = sharesIdentity "defaultText" "80" "443";
        visible = sharesIdentity "visible" true false;
        internal = sharesIdentity "internal" false true;
      };
      expected = {
        description = true;
        example = true;
        defaultText = true;
        visible = true;
        internal = true;
      };
    };
    # Behavioural attributes: `readOnly` decides whether an instance may define the option at all,
    # and `identity = false` removes a primitive option from the instance key set, yet a pair
    # differing there shares the KIND identity (instances still differ through their key sets).
    test-reopened-behavioural-attributes-share-identity-until-pa887-c = {
      expr = {
        readOnly = sharesIdentity "readOnly" false true;
        identity = sharesIdentity "identity" true false;
      };
      expected = {
        readOnly = true;
        identity = true;
      };
    };
    # Any attribute gen-merge does not know is carried on the declaration and is not a component.
    test-reopened-unknown-attribute-shares-identity-until-pa887-c = {
      expr = sharesIdentity "pa887Unknown" 1 2;
      expected = true;
    };
    # den-hoag-pa887 · the REGRESSION CELL. A kind whose option attribute other than `type`, or a
    # kind-level definition (plain or `mkDefault`), reads an instance's UNDECLARED `name` mints a
    # mark, and its instances mint an `id_hash` and read the value. One process per arm, on three
    # evaluators: the pa887 build report's probe. Before arm A this cell ABORTS (uncatchable
    # "attribute 'name' missing"), which takes the whole run down rather than failing the cell.
    # Such a term is not lost: its function module is a sealed component, so a pair differing only
    # there is refused (by name at 'modules': `kind-mark-cplus-refusal`).
    test-open-term-reading-instance-name-mints = {
      expr = {
        marks = map (k: builtins.isString (builtins.deepSeq k.__mint.minted k.__mint.minted)) (
          map (a: readsName a "x") [
            "default"
            "defaultText"
            "description"
            "example"
            "readOnly"
            "apply"
            "visible"
            "internal"
            "pa887Unknown"
          ]
          ++ [
            (definesName genMerge.mkDefault "x")
            (definesName (v: v) "x")
          ]
        );
        idHash = builtins.isString (instanceP (readsName "default" "x")).id_hash;
        defaultValue = (instanceP (readsName "default" "x")).p;
        definedIdHash = builtins.isString (instanceP (definesName genMerge.mkDefault "x")).id_hash;
        definedValue = (instanceP (definesName genMerge.mkDefault "x")).p;
        # ONE kind value: separately built twins of a function module are refused (znfjq's R1).
        reflexive =
          let
            k = readsName "default" "x";
          in
          kindEq k k;
        distinguished = decides (kindEq (readsName "default" "x") (readsName "default" "y"));
      };
      expected = {
        marks = builtins.genList (_: true) 11;
        idHash = true;
        defaultValue = "x-a";
        definedIdHash = true;
        definedValue = "x-a";
        reflexive = true;
        distinguished = false;
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
    # den-hoag-pa887: an open term reading an instance's `name` is distinguished by its function
    # module, the sealed `modules` component, and the collision is refused naming it.
    test-open-term-collision-names-its-module = {
      expr = kindEq (readsName "default" "x") (readsName "default" "y");
      expectedError = {
        type = "ThrownError";
        msg = "^gen-schema: kindEq: two declarations of 'host' mint one identity and differ, compared as values, only at sealed component\\(s\\) 'modules'; .*$";
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
