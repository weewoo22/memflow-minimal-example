{
  inputs = {
    flake-utils.url = github:numtide/flake-utils;
    zig-overlay.url = github:arqv/zig-overlay;
    memflow.url = github:memflow/memflow-nixos;
  };

  outputs = { self, nixpkgs, flake-utils, zig-overlay, memflow, ... } @ inputs:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };
        lib = pkgs.lib;
      in
      {

        devShell = pkgs.mkShell {
          MEMFLOW_CONNECTOR_INVENTORY_PATHS = lib.concatStringsSep ";" [
            "${memflow.packages.${system}.memflow-kvm}/lib/" # KVM Connector
            "${memflow.packages.${system}.memflow-win32}/lib/" # Win32 Connector plugin
          ];
          nativeBuildInputs = with pkgs; [
            zig-overlay.packages.${system}.master.latest # Zig compiler
            memflow.packages.${system}.memflow
            memflow.packages.${system}.memflow-kvm
            # pkg-config
          ];
        };

      });
}
