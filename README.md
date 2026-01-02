# Packer - Custom VM Images

Build custom cloud images with pre-installed packages for faster VM boot times.

## Prerequisites

```bash
apt install packer
git clone https://github.com/john-derose/packer.git
```

## Quick Start

```bash
cd /root/packer

# Build Debian 12 (Bookworm)
packer build templates/debian-12-base.pkr.hcl
# Output: output/debian-12-base.qcow2

# Build Debian 13 (Trixie)
packer build templates/debian-13-base.pkr.hcl
# Output: output/debian-13-base.qcow2
```

All images include `qemu-guest-agent` pre-installed.

## Image Serving (Deferred)

To serve images via HTTP for use with tofu `proxmox-file` module:

### Option 1: Simple Python HTTP Server

```bash
# Copy image to web directory
mkdir -p /var/www/images
cp output/debian-12-base.qcow2 /var/www/images/

# Start server (foreground, for testing)
cd /var/www/images && python3 -m http.server 8080

# Image URL: http://10.0.12.124:8080/debian-12-base.qcow2
```

### Option 2: Systemd Service (Persistent)

Create `/etc/systemd/system/image-server.service`:
```ini
[Unit]
Description=Simple HTTP server for VM images
After=network.target

[Service]
Type=simple
WorkingDirectory=/var/www/images
ExecStart=/usr/bin/python3 -m http.server 8080
Restart=always

[Install]
WantedBy=multi-user.target
```

Then:
```bash
systemctl daemon-reload
systemctl enable --now image-server
```

### Option 3: Nginx (Production)

```bash
apt-get install -y nginx

# Add to /etc/nginx/sites-available/default:
# location /images/ {
#     alias /var/www/images/;
#     autoindex on;
# }

systemctl restart nginx
# Image URL: http://10.0.12.124/images/debian-12-base.qcow2
```

## Using with Tofu

Once serving, update environment to use custom image:

```hcl
module "cloud_image" {
  source            = "../../proxmox-file"
  proxmox_node_name = var.proxmox_node_name
  source_file_url   = "http://10.0.12.124:8080/debian-12-base.qcow2"
  source_file_path  = "debian-12-base.qcow2"
}
```

Then simplify cloud-init (remove packages section since qemu-guest-agent is pre-installed).

## Build Time

- Full build: ~1-2 minutes
- Downloads Debian cloud image on first run (cached after)
