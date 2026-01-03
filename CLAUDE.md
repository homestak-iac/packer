# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Packer templates for building custom Debian cloud images with pre-installed packages. Images boot ~16s vs ~35s with stock images due to pre-installed qemu-guest-agent.

## Quick Reference

```bash
./build.sh       # Interactive menu to select and build a template
./publish.sh     # Copy images to /var/lib/vz/template/iso/
packer init templates/debian-12-custom.pkr.hcl   # Install QEMU plugin (first time)
packer validate templates/debian-12-custom.pkr.hcl  # Validate template syntax
```

## Project Structure

```
packer/
├── build.sh              # Interactive build script (logs to logs/)
├── publish.sh            # Checksum-based copy to Proxmox storage
├── templates/            # Packer HCL templates
│   ├── debian-12-custom.pkr.hcl
│   └── debian-13-custom.pkr.hcl
├── scripts/
│   └── cleanup.sh        # Template prep (cloud-init reset, module blacklist)
├── cloud-init/           # Build-time cloud-init (NoCloud datasource)
├── images/               # Built .qcow2 images (git-ignored)
├── cache/                # Downloaded base images (git-ignored)
└── logs/                 # Build logs with timestamps
```

## Build Workflow

```
templates/*.pkr.hcl
    ↓ ./build.sh (packer build -force)
images/*/*.qcow2
    ↓ ./publish.sh (rsync -c)
/var/lib/vz/template/iso/*-custom.img
    ↓ tofu apply (proxmox-file module)
VMs boot in ~16s
```

## Template Anatomy

Each template:
1. Downloads Debian cloud image to `cache/` (cached after first run)
2. Boots VM with cloud-init from `cloud-init/` directory
3. Installs qemu-guest-agent via shell provisioner
4. Runs `scripts/cleanup.sh` to prepare for templating
5. Outputs `.qcow2` to `images/<template-name>/`

## cleanup.sh Responsibilities

- Clears apt cache and lists
- Resets cloud-init state (`cloud-init clean --logs`)
- Truncates machine-id, hostname (regenerated on boot)
- Removes SSH host keys (regenerated on boot)
- Blacklists unnecessary kernel modules (cfg80211, floppy, joydev, psmouse, pcspkr)
- Rebuilds initramfs

## Related Projects

Part of the [homestak-dev](https://github.com/homestak-dev) organization:

| Repo | Purpose |
|------|---------|
| [ansible](https://github.com/homestak-dev/ansible) | Proxmox host configuration |
| [iac-driver](https://github.com/homestak-dev/iac-driver) | E2E test orchestration |
| [packer](https://github.com/homestak-dev/packer) | This project - custom cloud images |
| [tofu](https://github.com/homestak-dev/tofu) | VM provisioning (consumes images) |

## Prerequisites

- Packer with QEMU plugin (`packer init`)
- KVM/QEMU with nested virtualization
- SSH key at `~/.ssh/id_rsa` (used for cloud-init auth during build)
- ~10GB disk space for cached base images

## Conventions

- Template names: `debian-{version}-custom.pkr.hcl`
- Output names: `debian-{version}-custom.qcow2` → published as `.img`
- Build logs: `logs/{template}.{timestamp}.log`
- Build time: ~1.5-2 minutes per image

## License

Apache 2.0 - see [LICENSE](LICENSE)
