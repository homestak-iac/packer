# packer

Build custom Debian cloud images with pre-installed packages for faster VM boot times.

Part of the [homestak-dev](https://github.com/homestak-dev) organization.

## Quick Start

```bash
./build.sh      # Interactive build menu
./publish.sh    # Copy images to Proxmox storage
```

## Features

- **Pre-installed qemu-guest-agent** - ~16s boot vs ~35s with cloud-init install
- **Blacklisted modules** - No unnecessary drivers (wireless, floppy, joystick, etc.)
- **Smart publish** - Checksum-based copy skips unchanged images
- **lae.proxmox compatible** - grub-pc pre-configured for non-interactive kernel removal

## Project Structure

```
packer/
├── templates/          # Packer HCL templates
│   ├── debian-12-custom.pkr.hcl
│   └── debian-13-custom.pkr.hcl
├── scripts/
│   └── cleanup.sh      # Template preparation (cloud-init reset, module blacklist)
├── cloud-init/         # Build-time cloud-init config
├── images/             # Built images (git-ignored)
├── cache/              # Downloaded base images (git-ignored)
├── logs/               # Build logs
├── build.sh            # Interactive build script
└── publish.sh          # Copy images to Proxmox storage
```

## Workflow

```
templates/*.pkr.hcl
    ↓ ./build.sh
images/*/*.qcow2
    ↓ ./publish.sh
/var/lib/vz/template/iso/*-custom.img
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
- SSH key at `~/.ssh/id_rsa` (or set `ssh_private_key_file` variable)

## Build Times

- Debian 12: ~2 minutes
- Debian 13: ~1.5 minutes
- Base images cached after first download

## Releases

Pre-built images are available as GitHub Release assets.

**Download:**
```bash
gh release download --pattern '*.qcow2'
```

**Create a release:**
```bash
# Build images locally (requires KVM)
./build.sh

# Tag and push
git tag v1.0.0
git push origin v1.0.0

# Upload images to the release
gh release upload v1.0.0 images/debian-12/debian-12-custom.qcow2
gh release upload v1.0.0 images/debian-13/debian-13-custom.qcow2
```

## Related Repos

| Repo | Purpose |
|------|---------|
| [bootstrap](https://github.com/homestak-dev/bootstrap) | Entry point - curl\|bash setup |
| [site-config](https://github.com/homestak-dev/site-config) | Site-specific secrets and configuration |
| [ansible](https://github.com/homestak-dev/ansible) | Proxmox host configuration |
| [iac-driver](https://github.com/homestak-dev/iac-driver) | Orchestration engine (builds images, provisions VMs) |

## License

Apache 2.0 - see [LICENSE](LICENSE)
