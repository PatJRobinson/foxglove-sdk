{
  description = "A nix flake for PatJRobinson's fork of foxglove-sdk";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    nixpkgs,
    flake-utils,
    ...
  }:
    flake-utils.lib.eachSystem
    ["x86_64-linux" "aarch64-linux"]
    (
      system: let
        pkgs = import nixpkgs {
          inherit system;
        };
      in {
        packages.default = with pkgs;
          pkgs.rustPlatform.buildRustPackage rec {
            pname = "foxglove-sdk";
            version = "0.21.0";

            src = fetchFromGitHub {
              owner = "foxglove";
              repo = "foxglove-sdk";
              rev = "sdk/v${version}";
              hash = "sha256-kpUsoMXoLfNvu8PYWYt5fP/9gu8/0XyJkd/qIL6p++Y=";
            };

            cargoHash = "sha256-UmmTvZdCZQobHHG2OzzpzwEO7zABIz7e3l0275AfZHc=";

            nativeBuildInputs = [
              pkg-config
              cmake
              clang
              llvmPackages.libclang
              python3
            ];

            buildInputs = [
              openssl
              zlib
              glib
            ];

            CC = "${clang}/bin/clang";
            CXX = "${clang}/bin/clang++";

            LIBCLANG_PATH = "${lib.getLib llvmPackages.libclang}/lib";

            AWS_LC_SYS_CFLAGS = "-Wno-restrict -Wno-error=restrict -Wno-error=stringop-overflow";

            # Often helpful for bindgen on Nix so clang sees libc / C++ headers properly.
            BINDGEN_EXTRA_CLANG_ARGS =
              lib.optionalString stdenv.hostPlatform.isLinux
              "--sysroot=${stdenv.cc.libc.dev} "
              + lib.concatStringsSep " " [
                "-I${lib.getDev stdenv.cc.libc}/include"
                "-I${lib.getDev clang}/lib/clang/${llvmPackages.libclang.version}/include"
              ];

            doCheck = false;

            cargoBuildFlags = [
              "--manifest-path"
              "c/Cargo.toml"
              "--package"
              "foxglove_c"
              "--lib"
            ];

            cargoCheckFlags = [
              "--manifest-path"
              "c/Cargo.toml"
              "--package"
              "foxglove_c"
              "--lib"
            ];

            # We only want the release artifacts for the C layer plus the headers/sources
            # that downstream C++ consumers compile themselves.
            installPhase = ''
              runHook preInstall

              mkdir -p $out/include
              mkdir -p $out/src
              mkdir -p $out/lib
              mkdir -p $out/share

              # C headers
              cp -r c/include/. $out/include/

              # C++ headers/sources
              cp -r cpp/foxglove/include/. $out/include/
              cp -r cpp/foxglove/src/. $out/src/

              # Rust-built C static library
              libpath="$(find target -type f -name 'libfoxglove*.a' | head -n1)"

              # Schemas
              cp -r schemas $out/share

              if [ -z "$libpath" ]; then
                echo "error: could not find built static library under target" >&2
                echo "available files under target:" >&2
                find target -maxdepth 5 -type f | sort >&2 || true
                exit 1
              fi

              cp "$libpath" $out/lib/libfoxglove.a

              runHook postInstall
            '';

            passthru = {
              cmakeIncludeDirs = [
                "include"
                "include/foxglove"
              ];

              sourceGlobs = [
                "src/*.cpp"
                "src/server/*.cpp"
              ];

              staticLib = "lib/libfoxglove.a";
            };

            meta = with lib; {
              description = "Foxglove SDK packaged for downstream C++ builds";
              homepage = "https://github.com/foxglove/foxglove-sdk";
              license = licenses.mit;
              platforms = platforms.linux ++ platforms.darwin;
            };
          };
      }
    );
}
