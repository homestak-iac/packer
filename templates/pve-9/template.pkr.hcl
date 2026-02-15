packer {
  required_plugins {
    qemu = {
      version = "~> 1"
      source  = "github.com/hashicorp/qemu"
    }
  }
}

variable "output_name" {
  type    = string
  default = "pve-9.qcow2"
}

variable "ssh_private_key_file" {
  type        = string
  default     = "~/.ssh/id_rsa"
  description = "Path to SSH private key for packer to connect to build VM"
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key content for build VM authentication (passed by build.sh)"
}

locals {
  template_name = "pve-9"
}

source "qemu" "debian" {
  # Use Debian cloud image as base
  iso_url         = "https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2"
  iso_checksum    = "file:https://cloud.debian.org/images/cloud/trixie/latest/SHA512SUMS"
  iso_target_path = "cache/debian-13-generic-amd64.qcow2"
  disk_image      = true

  # Output settings
  output_directory = "images/pve-9"
  vm_name          = var.output_name
  format           = "qcow2"

  # VM settings for build - larger for PVE packages
  accelerator = "kvm"
  memory      = 4096
  cpus        = 2
  disk_size   = "20G"

  # Network - user mode networking with SSH forwarding
  net_device           = "virtio-net"
  communicator         = "ssh"
  ssh_username         = "root"
  ssh_timeout          = "20m"
  ssh_private_key_file = var.ssh_private_key_file

  # Cloud-init with dynamic SSH key injection
  cd_content = {
    "meta-data" = file("../../shared/cloud-init/meta-data")
    "user-data" = templatefile("../../shared/cloud-init/user-data.pkrtpl", {
      ssh_public_key = var.ssh_public_key
    })
  }
  cd_label = "cidata"

  # Headless mode (no display)
  headless = true

  # Wait for cloud-init to finish before trying SSH
  boot_wait = "60s"

  # Graceful shutdown
  shutdown_command = "shutdown -P now"

  # Serial console for debugging
  qemuargs = [
    ["-serial", "mon:stdio"],
  ]
}

build {
  sources = ["source.qemu.debian"]

  # Update, upgrade, and install qemu-guest-agent
  provisioner "shell" {
    inline = [
      "apt-get update",
      "DEBIAN_FRONTEND=noninteractive apt-get upgrade -y",
      "apt-get install -y qemu-guest-agent",
    ]
  }

  # Add Proxmox VE repository
  provisioner "shell" {
    inline = [
      "echo 'Adding Proxmox VE repository...'",
      "curl -fsSL -o /usr/share/keyrings/proxmox-archive-keyring-trixie.gpg https://enterprise.proxmox.com/debian/proxmox-archive-keyring-trixie.gpg",
      "chmod 644 /usr/share/keyrings/proxmox-archive-keyring-trixie.gpg",
      "printf '%s\\n' 'Types: deb' 'URIs: http://download.proxmox.com/debian/pve' 'Suites: trixie' 'Components: pve-no-subscription' 'Signed-By: /usr/share/keyrings/proxmox-archive-keyring-trixie.gpg' > /etc/apt/sources.list.d/pve-install-repo.sources",
    ]
  }

  # Install Proxmox VE packages (non-interactive)
  provisioner "shell" {
    inline = [
      "apt-get update",
      "echo 'Pre-seeding debconf for non-interactive installation...'",
      "echo 'grub-pc grub-pc/install_devices string /dev/vda' | debconf-set-selections",
      "echo 'grub-pc grub-pc/install_devices_empty boolean false' | debconf-set-selections",
      "echo 'postfix postfix/main_mailer_type select Local only' | debconf-set-selections",
      "echo 'Installing Proxmox VE packages (this takes ~10-15 minutes)...'",
      "DEBIAN_FRONTEND=noninteractive apt-get install -y proxmox-ve postfix open-iscsi chrony",
      "echo 'Proxmox VE packages installed successfully'",
    ]
  }

  # Detect versions for image naming
  provisioner "shell" {
    script = "${path.root}/../../shared/scripts/detect-versions.sh"
  }

  # Download version info for build script
  provisioner "file" {
    source      = "/tmp/image-version.txt"
    destination = "${path.root}/../../images/pve-9/image-version.txt"
    direction   = "download"
  }

  # Upload shared cleanup functions
  provisioner "file" {
    source      = "${path.root}/../../shared/scripts/cleanup-common.sh"
    destination = "/tmp/cleanup-common.sh"
  }

  # Clean up for templating
  provisioner "shell" {
    script = "${path.root}/cleanup.sh"
  }
}
