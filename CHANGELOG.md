# Changelog

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
