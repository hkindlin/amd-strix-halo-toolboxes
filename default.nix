# default.nix - For nix-build and nix-env users
#
# Build llama.cpp for AMD Strix Halo:
#   nix-build                        # Default (Vulkan)
#   nix-build -A llama-vulkan        # Vulkan backend
#   nix-build -A llama-rocm          # ROCm/HIP backend
#   nix-build -A vram-estimator      # VRAM estimation tool
#
# Install to user profile:
#   nix-env -f . -iA llama-vulkan
#
# For a better experience, use flakes:
#   nix build .#llama-vulkan
#   nix develop

let
  nixpkgs = fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/nixos-unstable.tar.gz";
  };
  
  pkgs = import nixpkgs {
    config = {
      allowUnfree = true;
      rocmSupport = true;
    };
  };

  # Use the nixpkgs llama-cpp with our overrides for simplicity
  # For the most optimized builds, use the flake which builds from source
  
  llamaVulkan = pkgs.llama-cpp.override {
    vulkanSupport = true;
    cudaSupport = false;
    rocmSupport = false;
  };

  llamaRocm = pkgs.llama-cpp.override {
    vulkanSupport = false;
    cudaSupport = false;
    rocmSupport = true;
  };

  vramEstimator = pkgs.writeScriptBin "gguf-vram-estimator" ''
    #!${pkgs.python3}/bin/python3
    ${builtins.readFile ./toolboxes/gguf-vram-estimator.py}
  '';

in {
  llama-vulkan = llamaVulkan;
  llama-rocm = llamaRocm;
  vram-estimator = vramEstimator;
  
  # Default to Vulkan (most stable)
  default = llamaVulkan;
}
