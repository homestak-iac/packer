# packer

Build custom Debian cloud images with pre-installed packages for faster VM boot times.

Part of the [homestak-dev](https://github.com/homestak-dev) organization.

## Quick Start

```bash
./build.sh              # Interactive build menu
./build.sh debian-12    # Build specific template
./publish.sh            # Copy images to Proxmox storage
```

## Features

- **Pre-installed qemu-guest-agent** - ~16s boot vs ~35s with cloud-init install
- **Blacklisted modules** - No unnecessary drivers (wireless, floppy, joystick, etc.)
- **Smart caching** - Skips rebuild when template and source image are unchanged
- **Smart publish** - Checksum-based copy skips unchanged images
- **lae.proxmox compatible** - grub-pc pre-configured for non-interactive kernel removal

## Available Templates

| Template | Image Size (compressed) | Boot Time | Build Time | Purpose |
|----------|------------------------|-----------|------------|---------|
| `debian-12` | ~780 MB | ~16s | ~2 min | Base Debian 12 with qemu-guest-agent |
| `debian-13` | ~590 MB | ~16s | ~1.5 min | Base Debian 13 with qemu-guest-agent |
| `pve-9` | ~3.4 GB | ~16s | ~15-20 min | PVE-ready with pre-installed packages |

## Project Structure

```
packer/
├── build.sh              # Interactive build script (caching, checksums)
├── publish.sh            # Checksum-based copy to Proxmox storage
├── checksums.sh          # Generate/verify SHA256 checksums
├── templates/            # Per-template directories
│   ├── debian-12/
│   │   ├── template.pkr.hcl
│   │   └── cleanup.sh
│   ├── debian-13/
│   │   ├── template.pkr.hcl
│   │   └── cleanup.sh
│   └── pve-9/
│       ├── template.pkr.hcl
│       └── cleanup.sh
├── shared/               # Shared resources across templates
│   ├── cloud-init/       # Build-time cloud-init config
│   └── scripts/          # Shared cleanup and detection scripts
├── images/               # Built .qcow2 images (git-ignored)
├── cache/                # Downloaded base images (git-ignored)
└── logs/                 # Build logs with timestamps
```

## Workflow

```
templates/{name}/template.pkr.hcl
    ↓ ./build.sh
images/{name}/{name}.qcow2
    ↓ ./publish.sh (qemu-img convert)
/var/lib/vz/template/iso/{name}.img
    ↓ iac-driver provisions VMs
VMs boot in ~16s (vs ~35s with generic cloud images)
```

## Module Blacklist

Images exclude unnecessary kernel modules for headless VMs:

- `cfg80211` - Wireless networking
- `floppy` - Floppy disk driver
- `joydev` - Joystick device
- `psmouse` - PS/2 mouse
- `pcspkr` - PC speaker

## Prerequisites

- **Packer 1.7+** from HashiCorp (Debian's 1.6.x doesn't support HCL2 `required_plugins`)
- KVM/QEMU with nested virtualization
- User in `kvm` group (`sudo usermod -aG kvm $USER`)

SSH keys are generated automatically per-build. To use an existing key: `SSH_KEY_FILE=~/.ssh/id_rsa ./build.sh`

## Releases

Pre-built images are available on the [`latest` GitHub Release](https://github.com/homestak-iac/packer/releases/tag/latest).

**Download via homestak CLI:**
```bash
homestak images download all --publish   # Download and install all images
```

**Or manually:**
```bash
gh release download latest --repo homestak-iac/packer --pattern '*.qcow2'
```

## Third-Party Acknowledgments

| Dependency | Purpose | License |
|------------|---------|---------|
| [hashicorp/qemu](https://github.com/hashicorp/packer-plugin-qemu) | QEMU builder plugin for Packer | MPL-2.0 |

## Related Repos

| Repo | Purpose |
|------|---------|
| [bootstrap](https://github.com/homestak/bootstrap) | Entry point - curl\|bash setup |
| [config](https://github.com/homestak/config) | Site-specific secrets and configuration |
| [ansible](https://github.com/homestak-iac/ansible) | Proxmox host configuration |
| [iac-driver](https://github.com/homestak-iac/iac-driver) | Orchestration engine (builds images, provisions VMs) |

## License

Apache 2.0 - see [LICENSE](LICENSE)
