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
  default = "debian-12-base.qcow2"
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
  net_device   = "virtio-net"
  communicator = "ssh"
  ssh_username = "root"
  ssh_timeout  = "10m"
  ssh_private_key_file = "/root/.ssh/id_rsa"

  # Cloud-init needs NoCloud datasource
  cd_files = ["./cloud-init/*"]
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
      "systemctl enable qemu-guest-agent",
    ]
  }

  # Clean up for templating
  provisioner "shell" {
    script = "scripts/cleanup.sh"
  }
}
