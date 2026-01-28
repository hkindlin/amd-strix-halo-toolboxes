# Compatibility shim for nix-shell users
# Redirects to the flake-based development shell
#
# Usage:
#   nix-shell                    # Default (Vulkan RADV)
#   nix-shell -A vulkan-radv     # Vulkan with Mesa RADV driver
#   nix-shell -A vulkan-amdvlk   # Vulkan with AMDVLK driver
#   nix-shell -A rocm            # ROCm/HIP backend
#
# For flake users (recommended):
#   nix develop                  # Default (Vulkan RADV)
#   nix develop .#vulkan-radv    # Vulkan with Mesa RADV
#   nix develop .#vulkan-amdvlk  # Vulkan with AMDVLK
#   nix develop .#rocm           # ROCm/HIP

let
  # Lock nixpkgs for reproducibility
  nixpkgs = fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/nixos-unstable.tar.gz";
  };
  
  pkgs = import nixpkgs {
    config = {
      allowUnfree = true;
      rocmSupport = true;
    };
  };

  # Llama.cpp source
  llamaCppSrc = pkgs.fetchFromGitHub {
    owner = "ggerganov";
    repo = "llama.cpp";
    rev = "master";
    sha256 = pkgs.lib.fakeSha256;  # Will error on first run - replace with actual hash
  };

  # Common CMake flags
  commonCmakeFlags = [
    "-DCMAKE_BUILD_TYPE=Release"
    "-DGGML_RPC=ON"
    "-DLLAMA_BUILD_TESTS=OFF"
    "-DLLAMA_BUILD_EXAMPLES=ON"
    "-DLLAMA_BUILD_SERVER=ON"
  ];

  # Vulkan build
  llamaCppVulkan = pkgs.stdenv.mkDerivation {
    pname = "llama-cpp-vulkan";
    version = "latest";
    src = llamaCppSrc;

    nativeBuildInputs = with pkgs; [ cmake ninja pkg-config shaderc ];
    buildInputs = with pkgs; [ vulkan-loader vulkan-headers curl openssl ];

    cmakeFlags = commonCmakeFlags ++ [ "-DGGML_VULKAN=ON" ];
  };

  # ROCm build
  llamaCppRocm = pkgs.stdenv.mkDerivation {
    pname = "llama-cpp-rocm";
    version = "latest";
    src = llamaCppSrc;

    nativeBuildInputs = with pkgs; [ cmake ninja pkg-config rocmPackages.llvm.clang ];
    buildInputs = with pkgs; [
      curl openssl
      rocmPackages.clr rocmPackages.rocm-runtime
      rocmPackages.rocblas rocmPackages.hipblas
      rocmPackages.rocm-device-libs rocmPackages.rocm-cmake
    ];

    cmakeFlags = commonCmakeFlags ++ [
      "-DGGML_HIP=ON"
      "-DAMDGPU_TARGETS=gfx1151"
      "-DLLAMA_HIP_UMA=ON"
      "-DROCM_PATH=${pkgs.rocmPackages.clr}"
    ];

    preConfigure = ''
      export ROCM_PATH="${pkgs.rocmPackages.clr}"
      export HIP_PATH="${pkgs.rocmPackages.clr}"
    '';
  };

  # VRAM estimator
  ggufVramEstimator = pkgs.writeScriptBin "gguf-vram-estimator" ''
    #!${pkgs.python3}/bin/python3
    ${builtins.readFile ./toolboxes/gguf-vram-estimator.py}
  '';

  # Python environment
  pythonEnv = pkgs.python3.withPackages (ps: with ps; [
    huggingface-hub hf-transfer requests
  ]);

  commonPackages = with pkgs; [
    pythonEnv ggufVramEstimator radeontop procps curl git
  ];

  shellHook = backend: ''
    echo ""
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║     AMD Strix Halo Llama.cpp Toolbox (${backend})             ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "⚠️  Note: For the best experience, use 'nix develop' with flakes!"
    echo ""
    echo "Quick Commands:"
    echo "  llama-cli --list-devices"
    echo "  llama-server -m model.gguf -c 8192 -ngl 999 -fa 1 --no-mmap"
    echo ""
  '';

in {
  # Default: Vulkan RADV
  vulkan-radv = pkgs.mkShell {
    name = "llama-vulkan-radv";
    packages = [ llamaCppVulkan ] ++ (with pkgs; [ vulkan-loader vulkan-tools mesa ]) ++ commonPackages;
    shellHook = ''
      export VK_ICD_FILENAMES="${pkgs.mesa}/share/vulkan/icd.d/radeon_icd.x86_64.json"
      export AMD_VULKAN_ICD=RADV
      ${shellHook "Vulkan RADV"}
    '';
  };

  # Alias for vulkan-radv (AMDVLK is deprecated in nixpkgs)
  vulkan = pkgs.mkShell {
    name = "llama-vulkan";
    packages = [ llamaCppVulkan ] ++ (with pkgs; [ vulkan-loader vulkan-tools mesa ]) ++ commonPackages;
    shellHook = ''
      export VK_ICD_FILENAMES="${pkgs.mesa}/share/vulkan/icd.d/radeon_icd.x86_64.json"
      export AMD_VULKAN_ICD=RADV
      ${shellHook "Vulkan RADV"}
    '';
  };

  rocm = pkgs.mkShell {
    name = "llama-rocm";
    packages = [ llamaCppRocm ] ++ (with pkgs; [
      rocmPackages.rocm-runtime rocmPackages.rocminfo
      rocmPackages.clr rocmPackages.rocblas rocmPackages.hipblas
    ]) ++ commonPackages;
    shellHook = ''
      export ROCM_PATH="${pkgs.rocmPackages.clr}"
      export HIP_PATH="${pkgs.rocmPackages.clr}"
      export HSA_OVERRIDE_GFX_VERSION="11.5.1"
      ${shellHook "ROCm/HIP"}
    '';
  };
}
