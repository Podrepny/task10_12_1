#!/bin/bash

SCRIPT_DIR=`dirname $0`
cd $SCRIPT_DIR

source config

## install packages
apt-get update
#apt-get upgrade
apt-get -y install ssh openssh-server git
apt-get -y install qemu-kvm libvirt-bin virtinst virt-viewer bridge-utils genisoimage
apt-get -y install mc virt-top libvirt-doc

## download virtual mashine
wget -c https://cloud-images.ubuntu.com/xenial/current/xenial-server-cloudimg-amd64-disk1.img || exit 1

# Create netwoks
# External
virsh net-define networks/external.xml
virsh net-autostart external
virsh net-start external
# Internal
virsh net-define networks/internal.xml
virsh net-autostart internal
virsh net-start internal
# Management
virsh net-define networks/management.xml
virsh net-autostart management
virsh net-start management

virsh net-list --all

## Create config iso for vm
genisoimage -output config-vm1.iso -volid cidata -joliet -rock config-drives/vm1-config/{user-data,meta-data}
genisoimage -output config-vm2.iso -volid cidata -joliet -rock config-drives/vm2-config/{user-data,meta-data}

mkdir -p /var/lib/libvirt/images/vm1/ /var/lib/libvirt/images/vm2/

qemu-img convert -O qcow2 xenial-server-cloudimg-amd64-disk1.img /var/lib/libvirt/images/vm1/vm1.qcow2

virt-install --name vm1 --ram 1024 --vcpus=2 --hvm --os-type=linux --os-variant=ubuntu16.04 --disk path=/var/lib/libvirt/images/vm1/vm1.qcow2,format=qcow2,bus=virtio,cache=none --disk path=config-vm1.iso,device=cdrom --network network=external,model=virtio --network network=internal,model=virtio --network network=management,model=virtio --graphics vnc,port=-1,listen=0.0.0.0 --noautoconsole --virt-type kvm

qemu-img convert -O qcow2 xenial-server-cloudimg-amd64-disk1.img /var/lib/libvirt/images/vm2/vm2.qcow2

virt-install --name vm2 --ram 1024 --vcpus=2 --hvm --os-type=linux --os-variant=ubuntu16.04 --disk path=/var/lib/libvirt/images/vm2/vm2.qcow2,format=qcow2,bus=virtio,cache=none --disk path=config-vm2.iso,device=cdrom --network network=internal,model=virtio --network network=management,model=virtio --graphics vnc,port=-1,listen=0.0.0.0 --noautoconsole --virt-type kvm

virsh list --all
