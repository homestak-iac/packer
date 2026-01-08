# Changelog

## v0.10 - 2026-01-08

### Documentation

- Add third-party acknowledgments for hashicorp/qemu builder

### CI/CD

- Add GitHub Actions workflow for `packer fmt` and `packer validate`

### Housekeeping

- Enable secret scanning and Dependabot

## v0.9 - 2026-01-07

### Features

- Add `debian-13-pve` PVE-ready image template (#12)
  - Pre-installs Proxmox VE packages for faster nested PVE deployment
  - Creates `/etc/pve-packages-preinstalled` marker for ansible detection
  - ~17 min time savings per nested-pve deployment
- Add compressed publishing support in `publish.sh`

## v0.8 - 2026-01-07

No changes - version bump for unified release.

## v0.7 - 2026-01-06

### Documentation

- Remove direct tofu references from documentation

## v0.6 - 2026-01-06

### Fixed

- **grub-pc debconf pre-configuration** - Images now pre-configure `grub-pc/install_devices` to `/dev/vda`, enabling non-interactive kernel removal when using `lae.proxmox` or similar automation tools (#1)

### Changed

- SSH key path now configurable via `ssh_private_key_file` variable (defaults to `/root/.ssh/id_rsa`)
- cloud-init/user-data updated with SSH keys for multiple build hosts

### Documentation

- Added grub-pc configuration details to CLAUDE.md
- Added Packer 1.7+ requirement (Debian's 1.6.x doesn't support HCL2 `required_plugins`)
- Added prerequisites section to README.md

## v0.5.0-rc1 - 2026-01-04

Consolidated pre-release with cloud images.

### Highlights

- debian-12-custom.qcow2 (~1.9 GB)
- debian-13-custom.qcow2 (~1.2 GB)
- Pre-installed qemu-guest-agent for fast boot (~16s)

### Note

Images are from v0.1.0-rc1 build (unchanged, proven stable).

### Changes

- Documentation improvements

## v0.1.0-rc1 - 2026-01-03

### Templates

- **debian-12**: Debian Bookworm cloud image with qemu-guest-agent
- **debian-13**: Debian Trixie cloud image with qemu-guest-agent

### Features

- Interactive build script (build.sh)
- Publish script for copying images to PVE storage (publish.sh)
- GitHub Releases for distributing built images

### Infrastructure

- Branch protection enabled (PR reviews for non-admins)
- Release artifacts attached to GitHub releases
