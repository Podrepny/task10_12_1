#!/bin/bash

SCRIPT_DIR=`dirname $0`
cd $SCRIPT_DIR

source config

## install packages
apt-get update
#apt-get upgrade
apt-get -y install vlan ssh openssh-server openssl git
apt-get -y qemu-kvm libvirt-bin virtinst virt-top libvirt-doc virt-viewer
apt-get -y mc
#modprobe 8021q

# Create netwoks
# External
# Internal
# Management


## download virtual mashine
wget https://cloud-images.ubuntu.com/xenial/current/xenial-server-cloudimg-amd64-disk1.img
## convert image to qcow
qemu-img convert -O qcow2 xenial-server-cloudimg-amd64-disk1.img xenial-server-cloudimg-amd64-disk1.img.qcow2
qemu-img resize xenial-server-cloudimg-amd64-disk1.img.qcow2 +10G
## create virtual mashine
virt-install -n web_devel -r 512 --disk path=/var/lib/libvirt/images/web_devel.img,bus=virtio,size=4 -c ubuntu-18.04-server-i386.iso --network network=default,model=virtio --graphics vnc,listen=0.0.0.0 --noautoconsole -v

## cloud-init
## configure vm1
## create meta-data for vm1

instance-id: iid-vm1
hostname: vm1
local-hostname: vm1
network-interfaces: |
  auto eth0
  iface eth0 inet dhcp
  
  auto eth1
  iface eth1 inet static
  address 192.168.124.11
  network 192.168.124.0
  netmask 255.255.255.0
  broadcast 192.168.124.255
  gateway 192.168.124.254
  dns-nameservers 8.8.8.8

  auto eth3
  iface eth3 inet dhcp

## create user-data for vm 1
#cloud-config
password: qwerty
chpasswd: { expire: False }
ssh_authorized_keys:
  - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC0aRs7Xw2SlI1eWPhYk0NbPvo4H+YN4qE+DybkbhVFE0GlzvSTyfuq0qjZ4lS1X6a1d4I9f3yao3MRRvGjxQ9jbcnyNd2nQsMbClNszkfCLa8GLz7n1e37VjEXM5u/na9fOot5SGdTJ86PMIa8xisMzXXWv302vE0d3J6dUobmzJGDo6J3kZN/OTmVrgt/cdNgrlGIqd1AcDhXzqKViKhWhC9CjbFRdNRPAFDlqHwVQZOPjM8ujR18MLUFmhiqigTnU4B+OAo1C7UabEFtph+GJRO/jiELc9LWr6RcSo4XIgosEsnnAE/i44zyEdhpP0b1WkGA0QqONKTlUS1tq/LV alexey@alexey-ubuntu

## network configuration
version: 1
config:
   - type: physical
     name: interface0
     mac_address: "52:54:00:12:34:00"
     subnets:
        - type: static
          address: 192.168.1.10
          netmask: 255.255.255.0
          gateway: 192.168.1.254

version: 2
ethernets:
  interface0:
     match:
         mac_address: "52:54:00:12:34:00"
     set-name: interface0
     addresses:
     - 192.168.1.10/255.255.255.0
     gateway4: 192.168.1.254

# example 3
network:
  version: 2
  ethernets:
    # opaque ID for physical interfaces, only referred to by other stanzas
    id0:
      match:
        macaddress: 00:11:22:33:44:55
      wakeonlan: true
      dhcp4: true
      addresses:
        - 192.168.14.2/24
        - 2001:1::1/64
      gateway4: 192.168.14.1
      gateway6: 2001:1::2
      nameservers:
        search: [foo.local, bar.local]
        addresses: [8.8.8.8]
    lom:
      match:
        driver: ixgbe
      # you are responsible for setting tight enough match rules
      # that only match one device if you use set-name
      set-name: lom1
      dhcp6: true
    switchports:
      # all cards on second PCI bus; unconfigured by themselves, will be added
      # to br0 below
      match:
        name: enp2*
      mtu: 1280
  bonds:
    bond0:
      interfaces: [id0, lom]
  bridges:
    # the key name is the name for virtual (created) interfaces; no match: and
    # set-name: allowed
    br0:
      # IDs of the components; switchports expands into multiple interfaces
      interfaces: [wlp1s0, switchports]
      dhcp4: true
  vlans:
    en-intra:
      id: 1
      link: id0
      dhcp4: yes
  # static routes
  routes:
   - to: 0.0.0.0/0
     via: 11.0.0.1
     metric: 3



# configure vm2

# create a disk to attach with some user-data and meta-data
genisoimage  -output seed.iso -volid cidata -joliet -rock user-data meta-data
