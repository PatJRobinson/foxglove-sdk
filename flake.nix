{
  description = "A nix flake for PatJRobinson's fork of foxglove-sdk";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-22.11";
    nixpkgs-rust.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-darwin.url = "github:NixOS/nixpkgs/nixos-25.11";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    nixpkgs,
    nixpkgs-rust,
    nixpkgs-darwin,
    flake-utils,
    ...
  }:
    flake-utils.lib.eachSystem
    ["x86_64-linux" "aarch64-linux" "aarch64-darwin"]
    (
      system: let
        nixpkgsForSystem =
          if builtins.match ".*-darwin" system != null
          then nixpkgs-darwin
          else nixpkgs;

        pkgs = import nixpkgsForSystem {
          inherit system;
        };

        rustPkgs = import nixpkgs-rust {
          inherit system;
        };

        rustPlatform = pkgs.makeRustPlatform {
          cargo = rustPkgs.cargo;
          rustc = rustPkgs.rustc;
        };
      in {
        packages.default = with pkgs;
          rustPlatform.buildRustPackage rec {
            pname = "foxglove-sdk";
            version = "0.21.0";

            src = fetchFromGitHub {
              owner = "foxglove";
              repo = "foxglove-sdk";
              rev = "sdk/v${version}";
              hash = "sha256-kpUsoMXoLfNvu8PYWYt5fP/9gu8/0XyJkd/qIL6p++Y=";
            };

            cargoHash =
              if stdenv.isDarwin
              then "sha256-UmmTvZdCZQobHHG2OzzpzwEO7zABIz7e3l0275AfZHc="
              else "sha256-7IqUjwPEj9jwuN4Mz3J6zC8O7fSApZviJDZ6H9BT8xg=";

            nativeBuildInputs = [
              pkg-config
              cmake
              clang
              llvmPackages.libclang
              python3
              rustPkgs.cargo
              rustPkgs.rustc
            ];

            buildInputs = [
              openssl
              zlib
              glib
            ];

            CC = 
              lib.optionalString stdenv.hostPlatform.isLinux
                "${clang}/bin/clang";

            CXX =
              lib.optionalString stdenv.hostPlatform.isLinux
                "${clang}/bin/clang++";

            LIBCLANG_PATH = "${lib.getLib llvmPackages.libclang}/lib";

            AWS_LC_SYS_CFLAGS = 
              lib.optionalString stdenv.hostPlatform.isLinux
                "-Wno-restrict -Wno-error=restrict -Wno-error=stringop-overflow";

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

            installPhase = ''
              runHook preInstall

              mkdir -p $out/include
              mkdir -p $out/src
              mkdir -p $out/lib
              mkdir -p $out/share
              mkdir -p $out/lib/cmake/FoxgloveSdk

              # C headers
              cp -r c/include/. $out/include/

              # C++ headers/sources
              cp -r cpp/foxglove/include/. $out/include/
              cp -r cpp/foxglove/src/. $out/src/

              # Schemas
              cp -r schemas $out/share/

              # Rust-built C static library
              libpath="$(find target -type f -name 'libfoxglove*.a' | head -n1)"

              if [ -z "$libpath" ]; then
                echo "error: could not find built static library under target" >&2
                echo "available files under target:" >&2
                find target -maxdepth 5 -type f | sort >&2 || true
                exit 1
              fi

              cp "$libpath" "$out/lib/libfoxglove.a"

              cat > $out/lib/cmake/FoxgloveSdk/FoxgloveSdkConfig.cmake <<'EOF'
              include(CMakeFindDependencyMacro)

              get_filename_component(_FOXGLOVE_SDK_PREFIX
                "''${CMAKE_CURRENT_LIST_DIR}/../../.."
                ABSOLUTE
              )

              set(FoxgloveSdk_INCLUDE_DIR "''${_FOXGLOVE_SDK_PREFIX}/include")
              set(FoxgloveSdk_LIBRARY "''${_FOXGLOVE_SDK_PREFIX}/lib/libfoxglove.a")
              set(FoxgloveSdk_SCHEMAS_DIR "''${_FOXGLOVE_SDK_PREFIX}/share/schemas")

              file(GLOB FoxgloveSdk_SOURCES
                "''${_FOXGLOVE_SDK_PREFIX}/src/*.cpp"
                "''${_FOXGLOVE_SDK_PREFIX}/src/server/*.cpp"
              )

              if(NOT TARGET FoxgloveSdk::foxglove)
                add_library(FoxgloveSdk::foxglove INTERFACE IMPORTED)
                set_target_properties(FoxgloveSdk::foxglove PROPERTIES
                  INTERFACE_INCLUDE_DIRECTORIES "''${_FOXGLOVE_SDK_PREFIX}/include"
                  INTERFACE_LINK_LIBRARIES "''${_FOXGLOVE_SDK_PREFIX}/lib/libfoxglove.a"
                )
              endif()
              EOF

              cat > $out/lib/cmake/FoxgloveSdk/FoxgloveSdkConfigVersion.cmake <<EOF
              set(PACKAGE_VERSION "${version}")
              if(PACKAGE_FIND_VERSION VERSION_EQUAL PACKAGE_VERSION)
                set(PACKAGE_VERSION_EXACT TRUE)
                set(PACKAGE_VERSION_COMPATIBLE TRUE)
              elseif(PACKAGE_FIND_VERSION VERSION_LESS PACKAGE_VERSION)
                set(PACKAGE_VERSION_COMPATIBLE TRUE)
              else()
                set(PACKAGE_VERSION_COMPATIBLE FALSE)
              endif()
              EOF

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
