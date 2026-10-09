{
  description = "-rede+social: build reproduzível dos serviços em Rust e ambiente de desenvolvimento";

  # O flake.lock fixa a versão exata do nixpkgs (e com ela o compilador Rust)
  # e vai para o repositório. É ele que garante que quem compilar hoje ou daqui
  # a um ano chega no mesmo binário, byte por byte.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      # nix build .#engine-server   (o motor que roda nos servidores)
      # nix build .#verificador     (o verificador aberto)
      # nix build .#cofre           (a linha de comando dos guardiões)
      #
      # Para conferir que o build é reproduzível, compile duas vezes:
      #   nix build .#engine-server && nix build .#engine-server --rebuild
      # O Nix recompila do zero e para com erro se um único byte mudar.
      packages = forAllSystems (pkgs:
        let
          # Só o código Rust entra no build: nada de target/, nem do resto
          # do repositório. Assim, mudar um texto do app não muda o binário.
          src = pkgs.lib.fileset.toSource {
            root = ./services;
            fileset = pkgs.lib.fileset.unions [
              ./services/Cargo.toml
              ./services/Cargo.lock
              ./services/ads-engine
              ./services/cofre
              ./services/engine-server
              ./services/feed-engine
              ./services/registro
              ./services/verificador
            ];
          };

          crate = pname: pkgs.rustPlatform.buildRustPackage {
            inherit pname src;
            version = "0.1.0";
            cargoLock.lockFile = ./services/Cargo.lock;
            cargoBuildFlags = [ "-p" pname ];
            # Os testes rodam na CI; alguns leem os parâmetros de ../params,
            # que ficam fora deste build de propósito.
            doCheck = false;
          };
        in
        {
          engine-server = crate "engine-server";
          verificador = crate "verificador";
          cofre = crate "cofre";
          default = crate "engine-server";
        });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.erlang_27
            pkgs.beam.packages.erlang_27.elixir_1_18
            pkgs.cargo
            pkgs.rustc
            pkgs.clippy
            pkgs.rustfmt
            pkgs.nodejs_22
            pkgs.postgresql_17
            pkgs.protobuf
          ];
        };
      });
    };
}
