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
    ↓ tofu apply
VMs boot in ~16s
```

## Using with Tofu

The tofu `proxmox-file` module supports local images:

```hcl
module "cloud_image" {
  source        = "../../proxmox-file"
  local_file_id = "local:iso/debian-12-custom.img"
}
```

## Module Blacklist

Images exclude unnecessary kernel modules for headless VMs:

- `cfg80211` - Wireless networking
- `floppy` - Floppy disk driver
- `joydev` - Joystick device
- `psmouse` - PS/2 mouse
- `pcspkr` - PC speaker

## Build Times

- Debian 12: ~2 minutes
- Debian 13: ~1.5 minutes
- Base images cached after first download

## Related Repos

| Repo | Purpose |
|------|---------|
| [ansible](https://github.com/homestak-dev/ansible) | Proxmox host configuration |
| [iac-driver](https://github.com/homestak-dev/iac-driver) | E2E test orchestration |
| [tofu](https://github.com/homestak-dev/tofu) | VM provisioning (consumes images) |

## License

Apache 2.0 - see [LICENSE](LICENSE)
