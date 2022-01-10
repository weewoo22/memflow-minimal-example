{
  inputs = {
    flake-utils.url = github:numtide/flake-utils;
    zig-overlay.url = github:arqv/zig-overlay;
    memflow.url = github:memflow/memflow-nixos;
  };

  outputs = { self, nixpkgs, flake-utils, zig-overlay, ... } @ inputs:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };
        lib = pkgs.lib;

        # Collect overridden package outputs into this variable
        memflowPkgs = builtins.mapAttrs
          (name: package:
            (package.overrideAttrs
              (super: {
                dontStrip = true;
                buildType = "debug";
              })
            )
          )
          inputs.memflow.packages.${system};
      in
      {

        devShell = pkgs.mkShell {
          MEMFLOW_CONNECTOR_INVENTORY_PATHS = with memflowPkgs; lib.concatStringsSep ";" [
            "${memflow-kvm}/lib/" # KVM Connector
            "${memflow-win32}/lib/" # Win32 Connector plugin
          ];
          nativeBuildInputs = with pkgs; with memflowPkgs; [
            zig-overlay.packages.${system}.master.latest # Zig compiler
            memflow
            memflow-kvm
          ];
        };

      }
    );
}
