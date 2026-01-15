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
  default = "debian-13-custom.qcow2"
}

variable "ssh_private_key_file" {
  type        = string
  default     = "~/.ssh/id_rsa"
  description = "Path to SSH private key for packer to connect to build VM"
}

locals {
  template_name = "debian-13-custom"
}

source "qemu" "debian" {
  # Use Debian cloud image as base
  iso_url         = "https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2"
  iso_checksum    = "file:https://cloud.debian.org/images/cloud/trixie/latest/SHA512SUMS"
  iso_target_path = "cache/debian-13-generic-amd64.qcow2"
  disk_image      = true

  # Output settings
  output_directory = "images/debian-13"
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

  # Cloud-init needs NoCloud datasource
  cd_files = ["shared/cloud-init/*"]
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

  # Install packages
  provisioner "shell" {
    inline = [
      "apt-get update",
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
    destination = "${path.root}/../../images/debian-13/image-version.txt"
    direction   = "download"
  }

  # Clean up for templating
  provisioner "shell" {
    script = "${path.root}/cleanup.sh"
  }
}
