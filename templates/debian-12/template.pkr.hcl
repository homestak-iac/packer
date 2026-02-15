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
  default = "debian-12.qcow2"
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
  template_name = "debian-12"
}

source "qemu" "debian" {
  # Use Debian cloud image as base
  iso_url         = "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2"
  iso_checksum    = "file:https://cloud.debian.org/images/cloud/bookworm/latest/SHA512SUMS"
  iso_target_path = "cache/debian-12-generic-amd64.qcow2"
  disk_image      = true

  # Output settings
  output_directory = "images/debian-12"
  vm_name          = var.output_name
  format           = "qcow2"

  # VM settings for build
  accelerator = "kvm"
  memory      = 2048
  cpus        = 2
  disk_size   = "10G"

  # Network - user mode networking with SSH forwarding
  net_device           = "virtio-net"
  communicator         = "ssh"
  ssh_username         = "root"
  ssh_timeout          = "10m"
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

  # Update, upgrade, and install packages
  provisioner "shell" {
    inline = [
      "apt-get update",
      "DEBIAN_FRONTEND=noninteractive apt-get upgrade -y",
      "apt-get install -y qemu-guest-agent",
    ]
  }

  # Detect versions for image naming
  provisioner "shell" {
    script = "${path.root}/../../shared/scripts/detect-versions.sh"
  }

  # Download version info for build script
  provisioner "file" {
    source      = "/tmp/image-version.txt"
    destination = "${path.root}/../../images/debian-12/image-version.txt"
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
