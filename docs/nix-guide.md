# NixOS / Nix Flake Guide

This project provides comprehensive Nix support for running Llama.cpp on AMD Strix Halo, enabling reproducible inference environments on NixOS and any system with Nix installed.

## Quick Start

### Using Flakes (Recommended)

```bash
# Enter the default shell (Vulkan RADV - most stable)
nix develop

# Or specify a backend explicitly:
nix develop .#vulkan-radv     # Vulkan with Mesa RADV (recommended)
nix develop .#vulkan          # Alias for vulkan-radv
nix develop .#rocm            # ROCm/HIP (AMD's compute stack)
```

### Using nix-shell

```bash
# Default shell
nix-shell

# Specific backends
nix-shell -A vulkan-radv
nix-shell -A vulkan          # Alias for vulkan-radv
nix-shell -A rocm
```

### Run Without Entering Shell

```bash
# Run llama-cli directly
nix run .#llama-cli -- --list-devices

# Run VRAM estimator
nix run .#vram-estimator -- /path/to/model.gguf
```

> **Note:** AMDVLK has been deprecated in nixpkgs. RADV is now the default and recommended Vulkan driver for AMD GPUs. If you need AMDVLK, you can use the Docker toolbox containers instead.

### Adding to `configuration.nix `

Add llama.cpp services to your NixOS system with automatic GPU support:

**1. Add to `/etc/nixos/flake.nix` (inputs):**
```nix
inputs = {
  nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  strix-halo-toolboxes.url = "github:hkindlin/amd-strix-halo-toolboxes";
};
```

**2. Add to `/etc/nixos/flake.nix` (modules):**
```nix
modules = [
  strix-halo-toolboxes.nixosModules.default
  ./configuration.nix
];
```

**3. Add to `/etc/nixos/configuration.nix`:**
```nix
services.strix-halo-llama = {
  enable = true;
  backend = "vulkan-radv";
  models = [
    {
      name = "fast";
      model = /mnt/models/mistral-7b.gguf;
      port = 8000;
    }
  ];
};
```

**4. Rebuild and activate:**
```bash
sudo nixos-rebuild switch
systemctl status 'strix-halo-llama-*'
curl http://localhost:8000/v1/models
```

## Configuration

### Single Model

For simple deployments with a single model, use the legacy single-model configuration:

```nix
{
  imports = [ strix-halo-toolboxes.nixosModules.default ];
  
  services.strix-halo-llama = {
    enable = true;
    backend = "vulkan-radv";
    model = /path/to/model.gguf;
    contextSize = 8192;
    port = 8000;
    host = "0.0.0.0";
  };
}
```

This creates a single systemd service: `strix-halo-llama.service`

### Multiple Models

Run multiple models simultaneously with automatic systemd service generation. Each model gets its own independent service with a unique port:

```nix
{
  imports = [ strix-halo-toolboxes.nixosModules.default ];
  
  services.strix-halo-llama = {
    enable = true;
    backend = "vulkan-radv";  # Default backend for all models
    
    models = [
      {
        name = "fast";
        model = /mnt/models/mistral-7b.gguf;
        port = 8000;
        host = "0.0.0.0";
      }
      {
        name = "large";
        model = /mnt/models/qwen-30b.gguf;
        port = 8001;
        host = "0.0.0.0";
        contextSize = 16384;  # Override for this model
      }
      {
        name = "reasoning";
        model = /mnt/models/qwen-reasoning.gguf;
        port = 8002;
        host = "0.0.0.0";
      }
    ];
  };
}
```

This automatically creates three systemd services:
- `strix-halo-llama-fast` (port 8000)
- `strix-halo-llama-large` (port 8001)
- `strix-halo-llama-reasoning` (port 8002)

All services use the global `backend = "vulkan-radv"` setting. Monitor all services with:

```bash
systemctl status 'strix-halo-llama-*'
journalctl -u 'strix-halo-llama-*' -f
```

### Multiple Models with Mixed Backends

Optionally, run Vulkan and ROCm models simultaneously on the same system. Each model can override the global backend setting:

```nix
{
  imports = [ strix-halo-toolboxes.nixosModules.default ];
  
  services.strix-halo-llama = {
    enable = true;
    backend = "vulkan-radv";  # Default backend
    
    models = [
      {
        name = "vulkan-fast";
        model = /mnt/models/mistral-7b.gguf;
        port = 8000;
        # Inherits global backend = "vulkan-radv"
      }
      {
        name = "rocm-large";
        model = /mnt/models/qwen-30b.gguf;
        port = 8001;
        backend = "rocm";  # Override to use ROCm for this model
        contextSize = 12000;
      }
      {
        name = "vulkan-reasoning";
        model = /mnt/models/qwen-reasoning.gguf;
        port = 8002;
        # Inherits global backend = "vulkan-radv"
      }
    ];
  };
}
```

This creates:
- `strix-halo-llama-vulkan-fast.service` (Vulkan RADV on port 8000)
- `strix-halo-llama-rocm-large.service` (ROCm/HIP on port 8001)
- `strix-halo-llama-vulkan-reasoning.service` (Vulkan RADV on port 8002)

**Use cases for mixed backends:**
- **Testing**: Compare inference speeds across backends with identical models
- **Backend-specific models**: Some models are optimized for ROCm, others for Vulkan
- **Workload distribution**: Fast inference on Vulkan, heavy processing on ROCm
- **Fallback strategy**: Keep a fast Vulkan model running while testing new ROCm models

### Adding to Your System's flake.nix

To integrate this project into your NixOS system, follow these steps:

#### Step 1: Update `/etc/nixos/flake.nix`

Add the strix-halo-toolboxes as an input:

```nix
{
  description = "My NixOS system configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    strix-halo-toolboxes.url = "git+file:///home/hk/prj/amd-strix-halo-toolboxes";
    
    # Or if you've forked it to GitHub:
    # strix-halo-toolboxes.url = "github:your-username/amd-strix-halo-toolboxes";
  };

  outputs = { nixpkgs, strix-halo-toolboxes, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        strix-halo-toolboxes.nixosModules.default  # ← Add this line
        ./configuration.nix
      ];
    };
  };
}
```

#### Step 2: Configure in `/etc/nixos/configuration.nix`

Add the services configuration. Here are common examples:

**Simple single model:**
```nix
services.strix-halo-llama = {
  enable = true;
  backend = "vulkan-radv";
  model = /mnt/models/mistral-7b.gguf;
  port = 8000;
};
```

**Multiple models with mixed backends:**
```nix
services.strix-halo-llama = {
  enable = true;
  backend = "vulkan-radv";  # Default for all models
  
  models = [
    {
      name = "fast";
      model = /mnt/models/mistral-7b.gguf;
      port = 8000;
    }
    {
      name = "large";
      model = /mnt/models/qwen-30b.gguf;
      port = 8001;
      contextSize = 16384;  # Override default
    }
    {
      name = "rocm-worker";
      model = /mnt/models/llama2-70b.gguf;
      port = 8002;
      backend = "rocm";  # Override to ROCm for this model
    }
  ];
};
```

#### Step 3: Rebuild and activate

```bash
sudo nixos-rebuild switch
```

#### Step 4: Verify services are running

```bash
# Check status
systemctl status 'strix-halo-llama-*'

# View logs for a specific model
journalctl -u strix-halo-llama-fast -f

# Query the API
curl http://localhost:8000/v1/models
```

### Options Reference

All available options for per-model configuration:

```nix
{
  name = "my-model";              # Service name: strix-halo-llama-my-model
  model = /path/to/model.gguf;    # Path to GGUF model file (required)
  port = 8000;                    # Port number for API (required)
  backend = "vulkan-radv";        # "vulkan-radv", "vulkan", "rocm" (optional, inherits global)
  contextSize = 8192;             # Context window size (optional, default 8192)
  host = "127.0.0.1";             # Listen address (optional, default "127.0.0.1")
  extraArgs = [ "--threads" "8" ]; # Additional llama-server arguments (optional)
}
```

## Service Management

Once your systemd services are active, manage them with standard systemd commands:

### Check Service Status

```bash
# Check all strix-halo-llama services
systemctl status 'strix-halo-llama-*'

# Check a specific model
systemctl status strix-halo-llama-fast
```

### View Logs

```bash
# View logs for a specific model
journalctl -u strix-halo-llama-fast -f

# View all llama services
journalctl -u 'strix-halo-llama-*' -f

# View last 50 lines
journalctl -u strix-halo-llama-fast -n 50
```

### Control Services

```bash
# Restart a specific model
systemctl restart strix-halo-llama-large

# Stop all models
systemctl stop 'strix-halo-llama-*'

# Start all models
systemctl start 'strix-halo-llama-*'
```

### Query Available Models

Each service provides the OpenAI-compatible `/v1/models` endpoint:

```bash
curl http://localhost:8000/v1/models
curl http://localhost:8001/v1/models
curl http://localhost:8002/v1/models
```

## Development and Testing

Enter a development shell with tools:

```bash
nix develop .#vulkan-radv     # Vulkan RADV
nix develop .#vulkan          # Alias for vulkan-radv
nix develop .#rocm            # ROCm/HIP
```

### List Available GPUs

```bash
llama-cli --list-devices
```

### Estimate VRAM Requirements

```bash
gguf-vram-estimator /path/to/model.gguf
```

### Run Inference

```bash
# Recommended to use similar flags
llama-cli \
  -m models/model.gguf \
  -c 8192 \
  -ngl 999 \
  -fa 1 \
  --no-mmap \
  -p "Write a haiku about Strix Halo"
```

### Start API Server

```bash
llama-server \
  -m models/model.gguf \
  -c 8192 \
  -ngl 999 \
  -fa 1 \
  --no-mmap \
  --host 0.0.0.0 \
  --port 8080
```

## Wrapper Scripts

The dev shells include convenience wrappers that automatically apply Strix Halo optimizations:

```bash
# Vulkan RADV (automatically adds: -fa 1 --no-mmap -ngl 999)
llama-radv -m model.gguf -c 8192 -p "Hello"
llama-server-radv -m model.gguf

# ROCm (automatically applies ROCm-specific flags)
llama-rocm -m model.gguf -c 8192 -p "Hello"
```

## Troubleshooting

### Vulkan device not found

```bash
# Verify Vulkan driver is available
ls /run/opengl-driver*/share/vulkan/icd.d/
echo $VK_ICD_FILENAMES
vulkaninfo --summary
```

### ROCm GPU not detected

```bash
# Verify kernel module is loaded
lsmod | grep amdgpu

# Check device file permissions
ls -la /dev/dri /dev/kfd

# Verify user group membership
groups
```

### Build failures

```bash
# Update the flake lock file
nix flake update

# Or pin to a specific llama.cpp version in flake.nix:
# llama-cpp-src.url = "github:ggerganov/llama.cpp/b1234...";
```

### Performance issues

- Ensure Strix Halo kernel parameters are set (see README section 6.2)
- Use `llama-cli --list-devices` to verify GPU detection
- Monitor with `watch -n 1 'rocm-smi'` or `watch -n 1 'vulkaninfo'`

## Package Development

### Building packages manually

```bash
nix build .#llama-vulkan
nix build .#llama-rocm
nix build .#vram-estimator
```

### Updating llama.cpp version

Edit `flake.nix` and update the `llama-cpp-src` input:

```bash
# Pin to a specific commit or tag
# llama-cpp-src.url = "github:ggerganov/llama.cpp/b1234abcd";

nix flake update llama-cpp-src
```

### Using the overlay in other projects

The flake provides an overlay for use in other Nix projects:

```nix
{
  inputs.strix-halo.url = "git+file:///home/hk/prj/amd-strix-halo-toolboxes";
  
  outputs = { nixpkgs, strix-halo, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      modules = [
        # Add the overlay to access strix-halo packages
        ({ config, pkgs, ... }: {
          nixpkgs.overlays = [ strix-halo.overlays.default ];
        })
      ];
    };
  };
}
```

## Advanced Configuration

### Per-Model Advanced Options

Each model supports fine-grained configuration:

```nix
models = [
  {
    name = "custom";
    model = /mnt/models/custom.gguf;
    port = 8000;
    backend = "rocm";                          # Backend override
    contextSize = 16384;                       # Context window
    host = "0.0.0.0";                         # Listen on all interfaces
    extraArgs = [
      "--threads" "16"
      "--batch-size" "512"
      "--ubatch-size" "256"
    ];
  }
];
```

### Using the NixOS Module Directly

If you don't use flakes, the module can be imported directly:

```nix
{
  imports = [ /path/to/amd-strix-halo-toolboxes/flake.nix ];
  # Then use services.strix-halo-llama as normal
}
```

## See Also

- **README.md**: Project overview and Strix Halo kernel parameter requirements
- **docs/troubleshooting-firmware.md**: GPU firmware and driver debugging

## Next Steps

1. **For development**: Use `nix develop .#vulkan-radv` to enter a shell with all tools
2. **For system integration**: Add the flake to your `/etc/nixos/flake.nix` and configure services
3. **For testing**: Use `nix run .#llama-cli -- --list-devices` to verify GPU detection
4. **For production**: Enable services with `nixos-rebuild switch` and monitor with systemctl
