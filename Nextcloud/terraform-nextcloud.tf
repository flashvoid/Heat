# Terraform config file

terraform {
  required_providers {
    openstack = {
      source = "terraform-provider-openstack/openstack"
    }
  }
}

provider "openstack" { 
  allow_reauth = false
}

# Parameters/Variables

variable "host_name" {
  description = "host name to associate with IP address"
  type = string
  default = "matcha"
}

variable "domain_name" {
  description = "domain name to associate with IP address"
  type = string
  default = "ilikebubbletea.me"
}

variable "ddns_script_url" {
  description = "URL of a script that will configure update ddns (called as ./ddns-script.sh <hostname> <ip> <password>)"
  type = string
  default = "https://raw.githubusercontent.com/flashvoid/demo-provision/main/ddns/namecheap/ddns-update"
}

variable "ddns_password" {
  description = "ddns password to use"
  type = string
  sensitive = true
  default = "ea2d5c1e46c14257aff7cf52c15515c3"
}

variable "setup_script_url" {
  description = "URL of a script that will configure docker containers (called as ./setup-script.sh <host_name> <domain_name> <ddns_password> <ip_address>)"
  type = string
  default = "https://raw.githubusercontent.com/yvonnewat/Heat/main/Nextcloud/setup-script.sh"
} 

variable "file_upload_size" {
  description = "The amount of file storage on the nextcloud instance, in MB"
  type = string
  default = "1024m"
}

variable "flavor_name" {
  description = "Flavor name for compute server"
  type = string
  default = "c1.c4r4"
}

variable "keyname" {
  description = "Keypair used for compute node"
  type = string
  default = "mykey"
}

variable "image_name" {
  description = "OS image for compute node"
  type = string
  default = "ubuntu-18.04-x86_64"
}

variable "volume_uuid" {
  description = "UUID of the volume a client wants to use for storage"
  type = string
  default = ""
}  

# Data

data "openstack_compute_flavor_v2" "flavor" {
  name = var.flavor_name
}

data "openstack_networking_network_v2" "public_net" {
  name = "public-net"
}

data "openstack_images_image_v2" "server_image" {
  name = var.image_name
  most_recent = true
}

# Resources

resource "openstack_networking_network_v2" "boba_network" {
  name = "boba_network"
}

resource "openstack_networking_subnet_v2" "boba_subnet" {
  network_id = openstack_networking_network_v2.boba_network.id
  name = "boba_subnet"
  cidr = "192.168.199.0/24"
}

resource "openstack_networking_router_v2" "boba_router" {
  name = "boba_router"
  external_network_id = data.openstack_networking_network_v2.public_net.id
}

resource "openstack_networking_router_interface_v2" "boba_interface" {
  router_id = openstack_networking_router_v2.boba_router.id
  subnet_id = openstack_networking_subnet_v2.boba_subnet.id
}

resource "openstack_networking_secgroup_v2" "boba_security_grp" {
  name = "boba_security_grp"
}

resource "openstack_networking_secgroup_rule_v2" "boba_security_group_rule1" {
  security_group_id = openstack_networking_secgroup_v2.boba_security_grp.id
  direction = "ingress"
  ethertype = "IPv4"
  protocol = "tcp"
  port_range_min = 22
  port_range_max = 22
  remote_ip_prefix  = "0.0.0.0/0"
}

resource "openstack_networking_secgroup_rule_v2" "boba_security_group_rule2" {
  security_group_id = openstack_networking_secgroup_v2.boba_security_grp.id
  direction = "ingress"
  ethertype = "IPv4"
  protocol = "tcp"
  port_range_min = 80
  port_range_max = 80
  remote_ip_prefix  = "0.0.0.0/0"
}

resource "openstack_networking_secgroup_rule_v2" "boba_security_group_rule3" {
  security_group_id = openstack_networking_secgroup_v2.boba_security_grp.id
  direction = "ingress"
  ethertype = "IPv4"
  protocol = "tcp"
  port_range_min = 443
  port_range_max = 443
  remote_ip_prefix  = "0.0.0.0/0"
}

resource "openstack_networking_port_v2" "boba_port" {
  name = "boba_port"
  network_id = openstack_networking_network_v2.boba_network.id
  security_group_ids = [ openstack_networking_secgroup_v2.boba_security_grp.id ]
  fixed_ip {
    subnet_id = openstack_networking_subnet_v2.boba_subnet.id
  }
}

resource "openstack_networking_floatingip_v2" "boba_floating_ip" {
  pool = data.openstack_networking_network_v2.public_net.name
}

resource "openstack_networking_floatingip_associate_v2" "boba_floating_ip_association" {
  floating_ip = openstack_networking_floatingip_v2.boba_floating_ip.address
  port_id = openstack_networking_port_v2.boba_port.id
}

resource "openstack_blockstorage_volume_v2" "boba_volume" {
  size = 20
  name = "boba_volume_data"
  volume_type = "b1.sr-r3-nvme-1000"
  #id = var.volume_uuid
  count = var.volume_uuid != "" ? 1 : 0
}

resource "openstack_compute_instance_v2" "qa_server" {
  name = "boba_nextcloud_server"
  key_pair = var.keyname

  flavor_id = data.openstack_compute_flavor_v2.flavor.id

  network {
    port = openstack_networking_port_v2.boba_port.id
  }
   block_device {
     delete_on_termination = true 
     source_type = "image"
     volume_size = 10
     destination_type = "volume"
     uuid = data.openstack_images_image_v2.server_image.id
     boot_index = 0
  }
   block_device {
     delete_on_termination = false
     uuid = openstack_blockstorage_volume_v2.boba_volume[count.index].id
     source_type = "volume"
     destination_type = "volume"
     boot_index = 1
  }
  user_data = templatefile("./cloud-init-docker.tpl", {
    domain_name = var.domain_name,
    host_name = var.host_name,
    ddns_password = var.ddns_password,
    ddns_script_url = var.ddns_script_url,
    ip_address = openstack_networking_floatingip_v2.boba_floating_ip.address,
    setup_script_url = var.setup_script_url,
    file_upload_size = var.file_upload_size
    })
}

output "floating_ip" {
  value = openstack_networking_floatingip_v2.boba_floating_ip.address
}
