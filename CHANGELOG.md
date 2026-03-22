# Changelog

## Unreleased

## v0.58 - 2026-03-22

No changes.

## v0.57 - 2026-03-22

No changes.

## v0.56 - 2026-03-09

No changes.

## v0.55 - 2026-03-08

No changes.

## v0.54 - 2026-03-08

### Changed
- Drop `.sh` extension from executable scripts (homestak-dev#313)
  - `build.sh` → `build`, `publish.sh` → `publish`, `checksums.sh` → `checksums`
- Update stale paths for multi-org migration (#65)
  - `site-config` → `config`, GitHub URLs updated to `homestak-iac/packer`

## v0.53 - 2026-03-06

No changes.

## v0.52 - 2026-03-02

No changes.

## v0.51 - 2026-02-28

No changes.

## v0.50 - 2026-02-22

### Added
- Add built image caching to `build.sh` — skip rebuild when template files and source image unchanged (#36)

### Changed
- Compress qcow2 output after build — `qemu-img convert -c` reclaims sparse space and applies zlib compression (#54)
  - pve-9: ~5.9 GB → ~3.4 GB, debian-12: ~1.9 GB → ~780 MB, debian-13: ~1.2 GB → ~590 MB
  - Checksums now reflect compressed images

### Removed
- Remove image splitting from `build.sh` — splitting moved to `release.sh packer --upload` (#52)
- Remove `copy-images.yml` workflow — replaced by `release.sh packer --upload` (#52)
- Remove `release.yml` workflow — `release.sh publish` is sole release creator (#52)
  - Cache key: composite SHA256 of source cloud image + template/shared files
  - `--force` flag bypasses cache; cache auto-invalidates on any file change
- Add `apt-get upgrade -y` to all build templates for security patch coverage (#50)

### Changed
- Simplify image naming: drop `-custom` suffix, rename `debian-13-pve` to `pve-9` (#48)
  - Template directories: `debian-12-custom` → `debian-12`, `debian-13-custom` → `debian-13`, `debian-13-pve` → `pve-9`
  - Output images: `debian-12.qcow2`, `debian-13.qcow2`, `pve-9.qcow2`
  - Simplified `build.sh`: removed versioned naming logic, simplified cache management
  - Simplified `publish.sh`: removed symlink creation

### Fixed
- Keep apt lists in packer images — stop removing `/var/lib/apt/lists/*` during cleanup so VMs boot with a usable apt cache (#47)

## v0.45 - 2026-02-02

- Release alignment with homestak v0.45

## v0.44 - 2026-02-02

- Release alignment with homestak v0.44

## v0.43 - 2026-02-01

- Release alignment with homestak v0.43

## v0.42 - 2026-01-31

### Changed
- Enhance copy-images.yml workflow (homestak-dev#146, homestak-dev#148)
  - Add `notes` input for custom release notes when copying images
  - Add `sync_latest` input to consolidate latest release sync
  - Workflow now handles both versioned release and latest sync in one pass
  - Eliminates redundant ~6GB transfer when using GHA workflow

## v0.41 - 2026-01-31

- Release alignment with homestak v0.41

## v0.33 - 2026-01-19

### Theme: Unit Testing

### Added
- Add bats tests for publish.sh (#42)
  - test/publish.bats - Image discovery, destination transforms, versioned names
  - Tests for --help, --version, --dry-run argument parsing
  - Tests for symlink handling and checksum file discovery

## v0.32 - 2026-01-19

### Added
- Add `--help` and `--version` to all scripts (build.sh, publish.sh, checksums.sh) (#40)
- Add `--dry-run` to publish.sh for previewing image publication (#40)
- Git-derived version pattern (no hardcoded VERSION constants)

### Fixed
- Resolve shellcheck warnings in build.sh and checksums.sh (#40)

## v0.31 - 2026-01-19

### Added
- Add bats tests for build scripts (#39)
  - test/build.bats - Template discovery, SSH key handling, checksums
  - test/checksums.bats - Checksum generation and verification
  - test/test_helper/common.bash - Shared fixtures and assertions
  - CI workflow runs tests on push/PR
  - `make test` target added

### Features
- Auto-split large images for GitHub release upload (#38)
  - Images >2GB are automatically split into ~1.9GB parts
  - Checksums generated for reassembled image
  - Parts named: `*.qcow2.partaa`, `*.qcow2.partab`, etc.
  - Reassemble with: `cat *.qcow2.part* > image.qcow2`

## v0.26 - 2026-01-17

- Release alignment with homestak v0.26

## v0.25 - 2026-01-16

- Release alignment with homestak v0.25

## v0.24 - 2026-01-16

- Release alignment with homestak v0.24

## v0.22 - 2026-01-15

### Features

- Add cache management options to build.sh (#33)
  - `--clean-cache`: Clear cached base images before building
  - `--auto-update`: Automatically clear stale cache and retry on checksum mismatch
  - `--help`: Show usage information
  - Clear error message with remediation suggestions on checksum failure

### Fixed

- Fix redundant -pve suffix in versioned image names (#34)
  - `debian-13-pve` now produces `deb13.x-pve9.x.qcow2` instead of `deb13.x-pve9.x-pve.qcow2`

- Fix copy-images workflow to support `latest` as target (.github#30)
  - Relaxed validation to accept `latest` OR `vX.Y` format
  - Auto-create `latest` release if it doesn't exist
  - Fix `force` parameter type in tag update API call (use `-F` for boolean)

- Fix cleanup script sourcing for per-template structure (#32)
  - Upload `cleanup-common.sh` to VM via file provisioner before sourcing
  - Scripts now source from `/tmp/cleanup-common.sh` on build VM

### Changed

- Dynamic SSH key injection for packer builds (#6)
  - Ephemeral keypair generated by default (no keys committed to repo)
  - Supports existing key via `SSH_KEY_FILE` environment variable
  - Converted `cloud-init/user-data` to template with dynamic key injection
  - Clear error messaging if specified key file not found

- Consolidate templates into per-template directories (#19)
  - New structure: `templates/{name}/template.pkr.hcl` with per-template `cleanup.sh`
  - Shared files moved to `shared/`: `cloud-init/`, `scripts/cleanup-common.sh`, `scripts/detect-versions.sh`
  - `build.sh` updated for new template discovery pattern
  - Cleaner separation between shared and template-specific files

- Generate per-image `.sha256` checksum files instead of consolidated `SHA256SUMS` (#25)
  - Follows Debian cloud image convention: `debian-12-custom.qcow2.sha256`
  - `build.sh` creates `.sha256` file after each build
  - `checksums.sh` updated for per-image file handling
  - Legacy `SHA256SUMS` files still displayed by `checksums.sh show`

### Documentation

- Add CI/CD section to CLAUDE.md documenting GitHub Actions workflow
- Add Known Issues section for AppArmor denials on Debian 13 (#27)
- Add KVM permissions requirement to prerequisites

## v0.20 - 2026-01-14

### Features

- Add per-template cleanup scripts (#11)
  - New `scripts/cleanup-common.sh` with shared cleanup functions
  - Per-template scripts: `debian-12-custom.cleanup.sh`, `debian-13-custom.cleanup.sh`, `debian-13-pve.cleanup.sh`
  - Templates use `fileexists()` for script discovery with fallback to `cleanup.sh`
  - PVE-specific cleanup: removes enterprise repo, adds cloud-init bootcmd for network fix

- Include version details in image names (#8)
  - New `scripts/detect-versions.sh` detects Debian and PVE versions during build
  - Images renamed with version info: `deb12.8-custom.qcow2`, `deb13.1-pve9.2-custom.qcow2`
  - Backward-compatible symlinks maintain old names (e.g., `debian-12-custom.qcow2`)
  - `publish.sh` creates symlinks in destination for tofu/site-config compatibility

## v0.19 - 2026-01-14

### Investigated

- Guest agent boot time on debian-13-pve (#13)
  - Tested: service disabling, guest agent priority, bootcmd→runcmd
  - Result: No improvement (133s vs 135s baseline)
  - Root cause likely cloud-init or nested virt overhead, not service contention
  - No code changes - investigation documented in issue

## v0.18 - 2026-01-13

### Features

- Add SHA256 checksums for image releases (#22)
  - `build.sh` generates per-image checksums after each build
  - New `checksums.sh` script for generate/verify/show operations
  - `publish.sh` copies SHA256SUMS alongside images

### CI/CD

- Add `.github/workflows/copy-images.yml` for cross-release image copying
  - Enables `release.sh packer --copy` automation
  - Downloads assets from source release, uploads to target

## v0.16 - 2026-01-11

- Release alignment with homestak v0.16

## v0.13 - 2026-01-10

- Release alignment with homestak-dev v0.13

## v0.12 - 2025-01-09

- Release alignment with homestak-dev v0.12

## v0.11 - 2026-01-08

- Release alignment with iac-driver v0.11

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
