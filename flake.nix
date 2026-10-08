{
  description = "-rede+social: ambiente de desenvolvimento reproduzível";

  # O flake.lock gerado na primeira execução fixa as versões exatas e deve ir
  # para o repositório. É ele que garante o mesmo ambiente para todo mundo.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
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
