{
  inputs = {
    unstable.url = github:NixOS/nixpkgs/nixos-unstable;
    flake-utils.url = github:numtide/flake-utils;
    zig-overlay.url = github:arqv/zig-overlay;
    rust-overlay.url = github:oxalica/rust-overlay;
  };

  outputs = { self, nixpkgs, flake-utils, zig-overlay, ... } @ inputs:
    flake-utils.lib.eachDefaultSystem (system:
      let
        overlays = [
          (import inputs.rust-overlay)
        ];
        pkgs = import nixpkgs {
          inherit system overlays;
        };
        lib = pkgs.lib;
        unstable_pkgs = import inputs.unstable {
          inherit system;
        };

        # See: https://github.com/memflow/memflow/commits/next
        memflowVersion = "ba80e0e974806d9386c5bf69c0beebedfb24a6bc";
        memflowSrc = pkgs.fetchFromGitHub {
          owner = "memflow";
          repo = "memflow";
          rev = memflowVersion;
          sha256 = "sha256-dFH0WUiX1gVoBKwylkOwAEj2T2lfFz0465ysh/LjEPs=";
        };

        # See: https://github.com/memflow/memflow-kvm/commits/next
        memflowKVMVersion = "0c542881a8f4f6219d7cca5dc0d438101f7bb206";
        memflowKVMSrc = pkgs.fetchFromGitHub {
          owner = "memflow";
          repo = "memflow-kvm";
          rev = "${memflowKVMVersion}";
          sha256 = "sha256-w4XRHpHMLPivbPpV1JB6RXFDZ6BlfRynN0HN899LWbg=";
          fetchSubmodules = true;
        };

        # See: https://github.com/memflow/memflow-win32/commits/main
        memflowWin32Version = "94ba500ccce4d0476c9415a4b304625e9d471069";
        memflowWin32Src = pkgs.fetchFromGitHub {
          owner = "memflow";
          repo = "memflow-win32";
          rev = "${memflowWin32Version}";
          sha256 = "sha256-hhgNRol8s9KXyUgn3nSczIIvYLdfmWT3JfE7jtYbVx0=";
        };
      in
      rec {
        devShell = pkgs.mkShell (rec {
          MEMFLOW_CONNECTOR_INVENTORY_PATHS = lib.concatStringsSep ";" [
            "${self.packages.${system}.memflow-kvm}/lib/" # KVM Connector
            "${self.packages.${system}.memflow-win32}/lib/" # Win32 Connector plugin
          ];
          nativeBuildInputs = with pkgs; [
            zig-overlay.packages.${system}.master.latest # Zig compiler
            self.packages.${system}.memflow
            self.packages.${system}.memflow-kvm
            pkg-config
          ];
        });

        packages = rec {

          cglue-bindgen =
            let
              src = pkgs.fetchFromGitHub {
                owner = "h33p";
                repo = "cglue";
                rev = "02e0f1089fe942edcda0391d12a008b6459bcc99";
                sha256 = "sha256-6+4ocKG9sAuZkT6AoOTBix3Sl6tifEXXexgo3w+YTC4=";
              };
              cargoTOML = (builtins.fromTOML (builtins.readFile (src + "/cglue-bindgen/Cargo.toml")));
            in
            pkgs.rustPlatform.buildRustPackage rec {
              pname = cargoTOML.package.name;
              version = cargoTOML.package.version;
              cargoHash = "sha256-qgPlAy/syKQIGfUjgDvFatzefUn6m77ARav5CbwyhNg=";
              inherit src;
              depsExtraArgs = {
                prePatch = ''
                  env CARGO_HOME=$(mktemp -d) cargo generate-lockfile
                '';
              };
              prePatch = ''
                cp ../cglue-*-vendor.tar.gz/Cargo.lock Cargo.lock
              '';
              meta = with lib; with cargoTOML.package; {
                inherit description;
                inherit homepage;
                downloadPage = https://github.com/h33p/cglue/releases;
                license = with licenses; [ mit ];
              };
            };

          memflow =
            let
              cargoTOML = (builtins.fromTOML (builtins.readFile (memflowSrc + "/memflow/Cargo.toml")));
            in
            pkgs.rustPlatform.buildRustPackage rec {
              pname = cargoTOML.package.name;
              version = memflowVersion;
              src = memflowSrc;
              doCheck = false;
              buildType = "debug";
              dontStrip = true;

              nativeBuildInputs = with pkgs; [
                breakpointHook
                # cbindgen 0.20 is needed for cglue-bindgen
                # See: https://github.com/h33p/cglue/blob/f419e046c624a2f46da8a32919d5d9db1d05f51b/cglue-bindgen/src/main.rs#L62
                unstable_pkgs.rust-cbindgen
                # Rust nightly is needed for cglue-bindgen:
                #
                # ERROR: Parsing crate `memflow-ffi`: couldn't run `cargo rustc -Zunpretty=expanded`:
                #
                # ...
                #
                # error: the option `Z` is only accepted on the nightly compiler
                # error: could not compile `memflow-ffi`
                rust-bin.nightly.latest.default
                self.packages.${system}.cglue-bindgen
              ];
              cargoHash = "sha256-pTg9zO5IIfeRCTh4N3mKsjeEych0tm1EktimTM3759o=";
              cargoBuildFlags = [ "--workspace" "--all-features" ];
              outputs = [ "dev" "out" ];
              patches = [
                ./patches/0001-bindgen_script_nix.patch
              ];
              depsExtraArgs = {
                prePatch = ''
                  # Make a temporary home directory to avoid sleeping in a homeless shelter
                  env CARGO_HOME=$(mktemp -d) cargo generate-lockfile # TODO: Should use $TMPDIR?
                '';
              };
              prePatch = ''
                cp ../memflow-*-vendor.tar.gz/Cargo.lock Cargo.lock
              '';
              postBuild = ''
                rm -f ./memflow-ffi/*.h{,pp}
                cd ./memflow-ffi/
                bash ./bindgen.sh || true
                bash ./bindgen.sh || true
                mkdir -vp "$dev/include/memflow/"
                cp -v ./memflow.h* "$dev/include/memflow/"
                cd ../.
              '';
              meta = with lib; with cargoTOML.package; {
                inherit description homepage;
                downloadPage = https://github.com/memflow/memflow/releases;
                license = with licenses; [ mit ];
              };
            };

          memflow-win32 =
            let
              cargoTOML = (builtins.fromTOML (builtins.readFile (memflowWin32Src + "/Cargo.toml")));
            in
            pkgs.rustPlatform.buildRustPackage (rec {
              pname = cargoTOML.package.name;
              version = memflowWin32Version;
              src = memflowWin32Src;
              dontStrip = true;
              buildType = "debug";

              cargoBuildFlags = [ "--workspace" "--all-features" ];
              cargoHash = "sha256-jSqH62RHd5EFdWpWEgD+nLMzBt8p1reBIhDAv8WYQ+8=";
              depsExtraArgs = {
                prePatch = ''
                  env CARGO_HOME=$(mktemp -d) cargo generate-lockfile
                '';
              };
              prePatch = ''
                cp ../memflow-win32-*-vendor.tar.gz/Cargo.lock Cargo.lock
              '';
            });

          memflow-kvm =
            let
              cargoTOML = (builtins.fromTOML (builtins.readFile (memflowKVMSrc + "/memflow-kvm/Cargo.toml")));
            in
            pkgs.rustPlatform.buildRustPackage (rec {
              name = cargoTOML.package.name;
              src = memflowKVMSrc;
              # See: https://nixos.org/manual/nixpkgs/stable/#building-a-package-in-debug-mode
              buildType = "debug";

              RUST_BACKTRACE = "full"; # note: Some details are omitted, run with `RUST_BACKTRACE=full` for a verbose backtrace.
              LIBCLANG_PATH = "${pkgs.libclang.lib}/lib"; # thread 'main' panicked at 'Unable to find libclang: "couldn\'t find any valid shared libraries matching: [\'libclang.so\', \'libclang-*.so\', \'libclang.so.*\', \'libclang-*.so.*\'], set the `LIBCLANG_PATH` environment variable to a path where one of these files can be found (invalid: [])"', /build/memflow-kvm-vendor.tar.gz/bindgen/src/lib.rs:1956:31

              cargoHash = "sha256-dCRFRBYdjmJJ12fmsD6eWxYNS7QB0HucfJyTHl31d8c=";
              dontStrip = true;
              # Compile the KVM connector in the same way memflowup does to ensure that the connector
              # implements the connector interface and contains the necessary exports
              # See: https://github.com/memflow/memflowup/blob/f44bb7a2d1338bd9d5fb546328fa37930dd2a755/memflowup.py#L113
              cargoBuildFlags = [ "--workspace" "--all-features" ];
              buildInputs = with pkgs; [
                llvmPackages.libclang
              ];
              nativeBuildInputs = with pkgs; [
                #breakpointHook
                rust-bindgen # ./mabi.h:14:10: fatal error: 'linux/types.h' file not found
              ];
              depsExtraArgs = {
                prePatch = ''
                  # Make a temporary home directory to avoid sleeping in a homeless shelter
                  env CARGO_HOME=$(mktemp -d) cargo generate-lockfile # TODO: Should use $TMPDIR?
                '';
              };
              prePatch = ''
                cp ../memflow-*-vendor.tar.gz/Cargo.lock Cargo.lock
              '';
            });

          # See: https://nixos.wiki/wiki/Linux_kernel#Packaging_out-of-tree_kernel_modules
          memflow-kmod = { _kernel, _nixpkgs, }: with _nixpkgs; stdenv.mkDerivation rec {
            name = "memflow-kmod-${memflowKVMVersion}-${_kernel.version}";
            src = memflowKVMSrc;
            preBuild = ''
              sed -e "s@/lib/modules/\$(.*)@${_kernel.dev}/lib/modules/${_kernel.modDirVersion}@" -i Makefile
            '';
            installPhase = ''
              mkdir -p "$out/lib/modules/${_kernel.modDirVersion}/misc/"
              cp ./build/memflow.ko $out/lib/modules/${_kernel.modDirVersion}/misc
            '';
            dontStrip = true;
            hardeningDisable = [ "format" "pic" ];
            kernel = _kernel.dev;
            nativeBuildInputs = _kernel.moduleBuildDependencies;
            meta = with lib; {
              # See: https://github.com/memflow/memflow-kvm#licensing-note
              license = with licenses; [ gpl2Only ];
            };
          };

        };
      }
    );
}
