{
  description = "face2face Expo and Cloudflare development environment";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      eachSystem = nixpkgs.lib.genAttrs systems;
      forSystem =
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          node = pkgs.nodejs_24;
          pnpm = pkgs.pnpm;
          source = pkgs.lib.cleanSourceWith {
            src = ./.;
            filter =
              path: type:
              let
                name = baseNameOf path;
              in
              !(builtins.elem name [
                "node_modules"
                ".git"
                ".jj"
                ".direnv"
                ".expo"
                ".wrangler"
                "dist"
                ".env"
                ".dev.vars"
                "result"
              ])
              && !(pkgs.lib.hasPrefix "result-" name);
          };
          package = pkgs.stdenvNoCC.mkDerivation {
            pname = "face2face";
            version = "0.1.0";
            src = source;
            nativeBuildInputs = [
              node
              pnpm
              pkgs.pnpmConfigHook
              pkgs.makeWrapper
            ]
            ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.autoPatchelfHook ];
            buildInputs = pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.stdenv.cc.cc.lib ];
            preBuild = pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
              autoPatchelf node_modules
            '';
            pnpmDeps = pkgs.fetchPnpmDeps {
              pname = "face2face";
              version = "0.1.0";
              src = source;
              inherit pnpm;
              fetcherVersion = 4;
              hash = "sha256-bBQdz0LtXNaiLvPX27VxGICAKGmIcfpPN7tLviLhRyA=";
            };
            EXPO_NO_TELEMETRY = "1";
            SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
            CI = "1";
            WRANGLER_SEND_METRICS = "false";
            buildPhase = ''
              runHook preBuild
              export HOME="$TMPDIR/home"
              mkdir -p "$HOME"
              pnpm build
              runHook postBuild
            '';
            doCheck = true;
            checkPhase = ''
              runHook preCheck
              pnpm fmt:check
              pnpm typecheck
              pnpm test
              runHook postCheck
            '';
            installPhase = ''
              runHook preInstall
              mkdir -p "$out/share/face2face" "$out/bin"
              cp -r apps/mobile/dist "$out/share/face2face/web"
              cp -r apps/api/dist "$out/share/face2face/worker"
              cp -r apps/api/migrations "$out/share/face2face/migrations"
              makeWrapper ${pkgs.python3}/bin/python3 "$out/bin/face2face-preview" \
                --add-flags '-m http.server --bind 127.0.0.1' \
                --add-flags "--directory $out/share/face2face/web" \
                --run 'if [ "$#" -eq 0 ]; then set -- 8081; fi'
              runHook postInstall
            '';
            meta.mainProgram = "face2face-preview";
          };
          task = name: command: {
            type = "app";
            meta.description = "Run the face2face ${name} task from the checkout";
            program = "${
              pkgs.writeShellApplication {
                name = "face2face-${name}";
                runtimeInputs = [
                  node
                  pnpm
                  pkgs.nixfmt
                ]
                ++ pkgs.lib.optionals (name == "tailscale") [ pkgs.tailscale ];
                text = ''
                  if [ ! -f pnpm-workspace.yaml ] || [ ! -f apps/api/wrangler.jsonc ]; then
                    echo 'Run this command from the face2face repository root.' >&2
                    exit 1
                  fi
                  ${command} "$@"
                '';
              }
            }/bin/face2face-${name}";
          };
        in
        {
          devShell = pkgs.mkShell {
            packages = [
              node
              pnpm
              pkgs.nixfmt
              pkgs.jujutsu
              pkgs.gh
              pkgs.sqlite
              pkgs.openssl
              pkgs.tailscale
            ];
            EXPO_NO_TELEMETRY = "1";
            WRANGLER_SEND_METRICS = "false";
          };
          formatter = pkgs.writeShellApplication {
            name = "face2face-nixfmt";
            runtimeInputs = [ pkgs.nixfmt ];
            text = ''
              if [ "$#" -eq 0 ]; then set -- flake.nix; fi
              exec nixfmt "$@"
            '';
          };
          inherit package;
          checks = {
            build = package;
            nix-format = pkgs.runCommand "face2face-nix-format" { nativeBuildInputs = [ pkgs.nixfmt ]; } ''
              nixfmt --check ${./flake.nix}
              touch "$out"
            '';
          };
          apps = {
            default = {
              type = "app";
              meta.description = "Serve the built face2face web preview";
              program = "${package}/bin/face2face-preview";
            };
            dev = task "dev" "exec pnpm dev";
            api = task "api" "exec pnpm dev:api";
            mobile = task "mobile" "exec pnpm dev:mobile";
            tailscale = task "tailscale" "exec pnpm dev:tailscale";
            build = task "build" "exec pnpm build";
            test = task "test" "exec pnpm test";
            lint = task "lint" "exec pnpm lint";
            fmt = task "fmt" "nixfmt flake.nix; exec pnpm fmt";
            fmt-check = task "fmt-check" "nixfmt --check flake.nix; exec pnpm fmt:check";
            check = task "check" "nixfmt --check flake.nix; exec pnpm check";
            typecheck = task "typecheck" "exec pnpm typecheck";
            db-migrate = task "db-migrate" "exec pnpm db:migrate";
          };
        };
    in
    {
      devShells = eachSystem (system: {
        default = (forSystem system).devShell;
      });
      formatter = eachSystem (system: (forSystem system).formatter);
      apps = eachSystem (system: (forSystem system).apps);
      packages = eachSystem (system: {
        default = (forSystem system).package;
      });
      checks = eachSystem (system: (forSystem system).checks);
    };
}
