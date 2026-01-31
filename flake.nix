{
  description = "AMD Strix Halo Llama.cpp Toolboxes - Nix Flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    # Pin llama.cpp source for reproducible builds
    llama-cpp-src = {
      url = "github:ggerganov/llama.cpp";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, llama-cpp-src }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
            rocmSupport = true;
          };
        };

        # ══════════════════════════════════════════════════════════════════
        # LLAMA.CPP BUILD CONFIGURATIONS
        # ══════════════════════════════════════════════════════════════════

        # Common CMake flags for all builds
        commonCmakeFlags = [
          "-DCMAKE_BUILD_TYPE=Release"
          "-DGGML_RPC=ON"
          "-DLLAMA_BUILD_TESTS=OFF"
          "-DLLAMA_BUILD_EXAMPLES=ON"
          "-DLLAMA_BUILD_SERVER=ON"
        ];

        # Vulkan-enabled llama.cpp (works with both RADV and AMDVLK)
        llamaCppVulkan = pkgs.stdenv.mkDerivation {
          pname = "llama-cpp-vulkan";
          version = "latest";
          src = llama-cpp-src;

          nativeBuildInputs = with pkgs; [
            cmake
            ninja
            pkg-config
            shaderc  # for glslc
          ];

          buildInputs = with pkgs; [
            vulkan-loader
            vulkan-headers
            curl
            openssl
          ];

          cmakeFlags = commonCmakeFlags ++ [
            "-DGGML_VULKAN=ON"
          ];

          meta = with pkgs.lib; {
            description = "Llama.cpp with Vulkan backend for AMD Strix Halo";
            homepage = "https://github.com/ggerganov/llama.cpp";
            license = licenses.mit;
            platforms = [ "x86_64-linux" ];
          };
        };

        # ROCm/HIP-enabled llama.cpp targeting gfx1151 (Strix Halo)
        llamaCppRocm = pkgs.stdenv.mkDerivation {
          pname = "llama-cpp-rocm";
          version = "latest";
          src = llama-cpp-src;

          nativeBuildInputs = with pkgs; [
            cmake
            ninja
            pkg-config
            rocmPackages.llvm.clang
          ];

          buildInputs = with pkgs; [
            curl
            openssl
            rocmPackages.clr           # HIP runtime
            rocmPackages.rocm-runtime
            rocmPackages.rocblas
            rocmPackages.hipblas
            rocmPackages.rocm-device-libs
            rocmPackages.rocm-cmake
          ];

          cmakeFlags = commonCmakeFlags ++ [
            "-DGGML_HIP=ON"
            "-DAMDGPU_TARGETS=gfx1151"
            "-DLLAMA_HIP_UMA=ON"
            "-DGGML_CUDA_ENABLE_UNIFIED_MEMORY=ON"
            "-DROCM_PATH=${pkgs.rocmPackages.clr}"
            "-DHIP_PATH=${pkgs.rocmPackages.clr}"
            "-DHIP_PLATFORM=amd"
          ];

          # Set up HIP environment
          preConfigure = ''
            export ROCM_PATH="${pkgs.rocmPackages.clr}"
            export HIP_PATH="${pkgs.rocmPackages.clr}"
            export HIP_CLANG_PATH="${pkgs.rocmPackages.llvm.clang}/bin"
            export HIP_DEVICE_LIB_PATH="${pkgs.rocmPackages.rocm-device-libs}/amdgcn/bitcode"
          '';

          meta = with pkgs.lib; {
            description = "Llama.cpp with ROCm/HIP backend for AMD Strix Halo (gfx1151)";
            homepage = "https://github.com/ggerganov/llama.cpp";
            license = licenses.mit;
            platforms = [ "x86_64-linux" ];
          };
        };

        # ══════════════════════════════════════════════════════════════════
        # HELPER UTILITIES
        # ══════════════════════════════════════════════════════════════════

        # VRAM estimation tool
        ggufVramEstimator = pkgs.writeScriptBin "gguf-vram-estimator" ''
          #!${pkgs.python3}/bin/python3
          ${builtins.readFile ./toolboxes/gguf-vram-estimator.py}
        '';

        # Python environment for HuggingFace downloads
        pythonEnv = pkgs.python3.withPackages (ps: with ps; [
          huggingface-hub
          hf-transfer
          requests
        ]);

        # Wrapper script for optimal Strix Halo settings
        llamaWrapper = llamaPkg: name: pkgs.writeShellScriptBin "llama-${name}" ''
          # Wrapper for llama-cli with optimal Strix Halo settings
          exec ${llamaPkg}/bin/llama-cli \
            -fa 1 \
            --no-mmap \
            -ngl 999 \
            "$@"
        '';

        serverWrapper = llamaPkg: name: pkgs.writeShellScriptBin "llama-server-${name}" ''
          # Wrapper for llama-server with optimal Strix Halo settings
          exec ${llamaPkg}/bin/llama-server \
            -fa 1 \
            --no-mmap \
            -ngl 999 \
            "$@"
        '';

        # ══════════════════════════════════════════════════════════════════
        # COMMON SHELL CONFIGURATION
        # ══════════════════════════════════════════════════════════════════

        commonShellHook = backend: ''
          echo ""
          echo "╔═══════════════════════════════════════════════════════════════╗"
          echo "║     AMD Strix Halo Llama.cpp Toolbox (${backend})             ║"
          echo "╚═══════════════════════════════════════════════════════════════╝"
          echo ""
          echo "📋 Quick Commands:"
          echo "   llama-cli --list-devices              # List GPU devices"
          echo "   llama-cli -m model.gguf -p 'prompt'   # Run inference"
          echo "   llama-server -m model.gguf            # Start API server"
          echo "   gguf-vram-estimator model.gguf        # Estimate VRAM usage"
          echo ""
          echo "⚠️  Critical Strix Halo Flags (auto-applied by wrappers):"
          echo "   -fa 1 --no-mmap -ngl 999"
          echo ""
          echo "📥 Download Models:"
          echo "   HF_HUB_ENABLE_HF_TRANSFER=1 huggingface-cli download \\"
          echo "     unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF \\"
          echo "     --local-dir models/"
          echo ""
        '';

        commonPackages = with pkgs; [
          pythonEnv
          ggufVramEstimator
          radeontop
          procps
          curl
          git
        ];

      in
      {
        # ══════════════════════════════════════════════════════════════════════
        # PACKAGES
        # ══════════════════════════════════════════════════════════════════════
        packages = {
          llama-vulkan = llamaCppVulkan;
          llama-rocm = llamaCppRocm;
          vram-estimator = ggufVramEstimator;
          default = llamaCppVulkan;
        };

        # ══════════════════════════════════════════════════════════════════════
        # DEVELOPMENT SHELLS
        # ══════════════════════════════════════════════════════════════════════
        devShells = {

          # ────────────────────────────────────────────────────────────────────
          # Vulkan with Mesa RADV - Most stable and compatible
          # ────────────────────────────────────────────────────────────────────
          vulkan-radv = pkgs.mkShell {
            name = "llama-vulkan-radv";

            packages = [
              llamaCppVulkan
              (llamaWrapper llamaCppVulkan "radv")
              (serverWrapper llamaCppVulkan "radv")
            ] ++ (with pkgs; [
              vulkan-loader
              vulkan-tools
              mesa
            ]) ++ commonPackages;

            shellHook = ''
              export VK_ICD_FILENAMES="${pkgs.mesa}/share/vulkan/icd.d/radeon_icd.x86_64.json"
              export AMD_VULKAN_ICD=RADV
              ${commonShellHook "Vulkan RADV"}
              echo "🎮 Backend: Mesa RADV (Vulkan)"
              echo "   Status: ✅ Most stable and recommended"
              echo ""
            '';
          };

          # ────────────────────────────────────────────────────────────────────
          # Vulkan alias (same as vulkan-radv)
          # Note: AMDVLK has been deprecated in nixpkgs, RADV is now default
          # ────────────────────────────────────────────────────────────────────
          vulkan = self.devShells.${system}.vulkan-radv;

          # ────────────────────────────────────────────────────────────────────
          # ROCm/HIP - AMD's GPU compute stack
          # ────────────────────────────────────────────────────────────────────
          rocm = pkgs.mkShell {
            name = "llama-rocm";

            packages = [
              llamaCppRocm
              (llamaWrapper llamaCppRocm "rocm")
              (serverWrapper llamaCppRocm "rocm")
            ] ++ (with pkgs; [
              rocmPackages.rocm-runtime
              rocmPackages.rocminfo
              rocmPackages.clr
              rocmPackages.rocblas
              rocmPackages.hipblas
            ]) ++ commonPackages;

            shellHook = ''
              export ROCM_PATH="${pkgs.rocmPackages.clr}"
              export HIP_PATH="${pkgs.rocmPackages.clr}"
              export HSA_OVERRIDE_GFX_VERSION="11.5.1"
              export HIP_VISIBLE_DEVICES=0
              ${commonShellHook "ROCm/HIP"}
              echo "🎮 Backend: ROCm/HIP"
              echo "   Target: gfx1151 (Strix Halo)"
              echo ""
              echo "🔍 Verify GPU detection:"
              echo "   rocminfo | grep -A5 'Agent 2'"
              echo ""
            '';
          };

          # ────────────────────────────────────────────────────────────────────
          # Default shell
          # ────────────────────────────────────────────────────────────────────
          default = self.devShells.${system}.vulkan-radv;
        };

        # ══════════════════════════════════════════════════════════════════════
        # APPS
        # ══════════════════════════════════════════════════════════════════════
        apps = {
          llama-cli = {
            type = "app";
            program = "${llamaCppVulkan}/bin/llama-cli";
          };
          llama-server = {
            type = "app";
            program = "${llamaCppVulkan}/bin/llama-server";
          };
          vram-estimator = {
            type = "app";
            program = "${ggufVramEstimator}/bin/gguf-vram-estimator";
          };
          default = self.apps.${system}.llama-cli;
        };
      }
    ) // {
      # ════════════════════════════════════════════════════════════════════════
      # NIXOS MODULE
      # ════════════════════════════════════════════════════════════════════════
      nixosModules.default = { config, lib, pkgs, ... }:
        with lib;
        let
          cfg = config.services.strix-halo-llama;
          
          
          modelSubmodule = types.submodule ({ config, ... }: {
            options = {
              name = mkOption {
                type = types.str;
                description = "Name/ID for this model instance";
                example = "model1";
              };

              model = mkOption {
                type = types.str;
                description = "Path to GGUF model file";
              };

              backend = mkOption {
                type = types.nullOr (types.enum [ "vulkan-radv" "vulkan" "rocm" ]);
                default = null;
                description = "GPU backend for this model. If null, uses global backend";
              };

              port = mkOption {
                type = types.port;
                description = "Server port for this instance";
              };

              contextSize = mkOption {
                type = types.int;
                default = 8192;
                description = "Context window size in tokens";
              };

              host = mkOption {
                type = types.str;
                default = "127.0.0.1";
                description = "Server bind address";
              };

              idleTimeout = mkOption {
                type = types.nullOr types.int;
                default = null;
                description = "Seconds of inactivity before unloading model (like Ollama). Null = never unload";
                example = 300;
              };

              extraArgs = mkOption {
                type = types.listOf types.str;
                default = [ ];
                description = "Additional arguments for llama-server";
              };
            };
          });
        in
        {
          options.services.strix-halo-llama = {
            enable = mkEnableOption "Llama.cpp server(s) optimized for AMD Strix Halo";

            backend = mkOption {
              type = types.enum [ "vulkan-radv" "vulkan" "rocm" ];
              default = "vulkan-radv";
              description = "GPU backend to use for all instances";
            };

            # Legacy single-model support (backwards compatible)
            model = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "DEPRECATED: Use 'models' instead. Path to a single GGUF model file";
            };

            port = mkOption {
              type = types.nullOr types.port;
              default = null;
              description = "DEPRECATED: Use 'models' instead. Server port for single model";
            };

            contextSize = mkOption {
              type = types.int;
              default = 8192;
              description = "Default context window size for all models";
            };

            host = mkOption {
              type = types.str;
              default = "0.0.0.0";
              description = "Default bind address for all instances";
            };

            # New multi-model support
            models = mkOption {
              type = types.listOf modelSubmodule;
              default = [ ];
              description = "List of models to run. If empty and 'model'/'port' are set, uses legacy mode";
              example = [
                { name = "fast"; model = /path/to/fast.gguf; port = 8000; }
                { name = "large"; model = /path/to/large.gguf; port = 8001; }
                { name = "reasoning"; model = /path/to/reasoning.gguf; port = 8002; }
              ];
            };

            extraArgs = mkOption {
              type = types.listOf types.str;
              default = [ ];
              description = "Additional global arguments for all llama-server instances";
            };

            idleTimeout = mkOption {
              type = types.nullOr types.int;
              default = null;
              description = ''Seconds of inactivity before unloading model from memory (similar to Ollama).
                Set to 0 for immediate unload after each request, null to never unload.
                Can be overridden per-model.'';
              example = 300;
            };

            startupDelay = mkOption {
              type = types.int;
              default = 10;
              description = ''Seconds to wait after boot before starting llama-server.
                This prevents ROCm crashes when the GPU is not fully initialized.
                Set to 0 to disable (not recommended for ROCm).'';
            };

            _modelsToRun = mkOption {
              type = types.listOf modelSubmodule;
              internal = true;
              description = "Internal option: computed list of models to run";
            };
          };

          config = mkIf cfg.enable {
            # Create static user for llama-server
            users.users.llama-server = {
              isSystemUser = true;
              group = "llama-server";
              extraGroups = [ "video" "render" ];
            };
            users.groups.llama-server = {};

            # Required for GPU access
            boot.kernelModules = [ "amdgpu" ];
            hardware.graphics.enable = true;

            # ROCm-specific configuration
            hardware.graphics.extraPackages = mkIf (cfg.backend == "rocm") [
              pkgs.rocmPackages.clr.icd
            ];

            # Build list of models: use 'models' if set, otherwise fall back to legacy single-model
            services.strix-halo-llama._modelsToRun = 
              if cfg.models != [] then cfg.models
              else if cfg.model != null && cfg.port != null then [
                { 
                  name = "default";
                  model = cfg.model;
                  port = cfg.port;
                  contextSize = cfg.contextSize;
                  host = cfg.host;
                  idleTimeout = cfg.idleTimeout;
                  extraArgs = cfg.extraArgs;
                }
              ]
              else [ ];

            # Create a systemd service for each model
            systemd.services = 
              let
                modelsToRun = config.services.strix-halo-llama._modelsToRun;
                
                # Helper to get the right llama package for a backend
                getLlamaPkg = backend:
                  let
                    effectiveBackend = if backend == null then cfg.backend else backend;
                  in
                  if effectiveBackend == "rocm"
                    then self.packages.${pkgs.system}.llama-rocm
                    else self.packages.${pkgs.system}.llama-vulkan;
                
                makeService = model: {
                  "strix-halo-llama-${model.name}" = 
                    let
                      effectiveBackend = if model.backend == null then cfg.backend else model.backend;
                      llamaPkg = getLlamaPkg model.backend;
                      # Use per-model idleTimeout if set, otherwise global, otherwise null
                      effectiveIdleTimeout = if model.idleTimeout != null then model.idleTimeout else cfg.idleTimeout;
                      idleTimeoutArgs = lib.optionalString (effectiveIdleTimeout != null) "--idle-timeout ${toString effectiveIdleTimeout}";
                    in
                    {
                      description = "Llama.cpp Server - ${model.name} [${effectiveBackend}] (Strix Halo)";
                      wantedBy = [ "multi-user.target" ];
                      
                      # Wait for GPU hardware to be ready - critical for ROCm stability on boot
                      after = [ "network.target" "systemd-udev-settle.service" ];
                      wants = [ "systemd-udev-settle.service" ];
                      
                      # Retry multiple times with increasing delays on boot failures
                      startLimitIntervalSec = 300;
                      startLimitBurst = 5;

                      environment = (lib.optionalAttrs (effectiveBackend == "rocm") {
                        HSA_OVERRIDE_GFX_VERSION = "11.5.1";
                        LD_LIBRARY_PATH = lib.makeLibraryPath [
                          pkgs.rocmPackages.clr
                          pkgs.rocmPackages.rocm-runtime
                          pkgs.rocmPackages.rocblas
                          pkgs.rocmPackages.hipblas
                        ];
                      }) // (lib.optionalAttrs (effectiveBackend == "vulkan-radv" || effectiveBackend == "vulkan") {
                        AMD_VULKAN_ICD = "RADV";
                      });

                      serviceConfig = {
                        Type = "simple";
                        
                        # Startup delay to ensure GPU is fully initialized (prevents ROCm race conditions)
                        ExecStartPre = lib.mkIf (cfg.startupDelay > 0) "${pkgs.coreutils}/bin/sleep ${toString cfg.startupDelay}";
                        
                        ExecStart = ''
                          ${llamaPkg}/bin/llama-server \
                            -m ${model.model} \
                            -c ${toString model.contextSize} \
                            -ngl 999 -fa 1 --no-mmap \
                            --host ${model.host} --port ${toString model.port} \
                            ${idleTimeoutArgs} \
                            ${concatStringsSep " " model.extraArgs}
                        '';

                        Restart = "on-failure";
                        RestartSec = 10;
                        
                        User = "llama-server";
                        Group = "llama-server";
                        SupplementaryGroups = [ "video" "render" ];
                        
                        # Security hardening
                        ProtectHome = true;
                        PrivateTmp = true;
                        NoNewPrivileges = true;
                        ProtectKernelModules = true;
                        ProtectKernelLogs = true;
                        ProtectControlGroups = true;
                        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
                        RestrictNamespaces = true;
                        LockPersonality = true;
                        RestrictRealtime = true;
                        RestrictSUIDSGID = true;
                        RemoveIPC = true;
                        PrivateMounts = true;
                      };
                    };
                };
              in
              foldl recursiveUpdate { } (map makeService modelsToRun);
          };
        };

      # ════════════════════════════════════════════════════════════════════════
      # OVERLAY
      # ════════════════════════════════════════════════════════════════════════
      overlays.default = final: prev: {
        strix-halo = {
          llama-vulkan = self.packages.${prev.system}.llama-vulkan;
          llama-rocm = self.packages.${prev.system}.llama-rocm;
          vram-estimator = self.packages.${prev.system}.vram-estimator;
        };
      };
    };
}
