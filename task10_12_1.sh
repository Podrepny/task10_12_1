#!/bin/bash

SCRIPT_DIR=`dirname $0`
cd ${SCRIPT_DIR}

source config
source function.inc

XML_PATH="networks"
CLOUDINIT_CONF_DIR="config-drives"
CLOUDINIT_CONF_DIR_SUFIX="-config"
VI_BR_PREFIX="virbr"
EXT_DHCP_IP_RANGE_BEGIN="2"
EXT_DHCP_IP_RANGE_END="254"
EXT_VM1_MAC=52:54:00:`(date; cat /proc/interrupts) | md5sum | sed -r 's/^(.{6}).*$/\1/; s/([0-9a-f]{2})/\1:/g; s/:$//;'`
#EXT_VIBR_NAME="${VI_BR_PREFIX}${EXTERNAL_NET##*.}"
EXT_VIBR_NAME="${VI_BR_PREFIX}-${VM1_EXTERNAL_IF}"
EXT_XML_PATH="${XML_PATH}/${EXTERNAL_NET_NAME}.xml"
#INT_VIBR_NAME="${VI_BR_PREFIX}${INTERNAL_NET##*.}"
INT_VIBR_NAME="${VI_BR_PREFIX}-${VM1_INTERNAL_IF}"
INT_XML_PATH="${XML_PATH}/${INTERNAL_NET_NAME}.xml"
#MGM_VIBR_NAME="${VI_BR_PREFIX}${MANAGEMENT_NET##*.}"
MGM_VIBR_NAME="${VI_BR_PREFIX}-${VM1_MANAGEMENT_IF}"
MGM_XML_PATH="${XML_PATH}/${MANAGEMENT_NET_NAME}.xml"

## generate id_rsa
if [ ! -e $SSH_PUB_KEY ]; then 
  ssh-keygen -t rsa -b 4096 -f ${SSH_PUB_KEY%.pub} -q -N ""
fi

## install packages
apt-get update
apt-get -y install ssh openssh-server
apt-get -y install qemu-kvm libvirt-bin virtinst virt-viewer bridge-utils genisoimage
apt-get -y install mc virt-top libvirt-doc git

## download virtual mashine
wget -c ${VM_BASE_IMAGE} || exit 1

## create netwoks config
## make dir for xml files
mkdir -p ${XML_PATH}
## generate external.xml
func_gen_conf_ext
## generate internal.xml
func_gen_conf_int
## generate management.xml
func_gen_conf_mgm
## define and start all networks
func_create_net ${EXTERNAL_NET_NAME} ${EXT_XML_PATH}
func_create_net ${INTERNAL_NET_NAME} ${INT_XML_PATH}
func_create_net ${MANAGEMENT_NET_NAME} ${MGM_XML_PATH}

# debug 
virsh net-list --all

## make user-data and meta-data  based on config
func_gen_cludinit_conf_vm1 "${CLOUDINIT_CONF_DIR}/${VM1_NAME}${CLOUDINIT_CONF_DIR_SUFIX}"
func_gen_cludinit_conf_vm2 "${CLOUDINIT_CONF_DIR}/${VM2_NAME}${CLOUDINIT_CONF_DIR_SUFIX}"

## deploy vm`s
func_deploy_vm ${VM1_NAME} ${VM1_HDD} ${VM1_CONFIG_ISO} "--network network=${EXTERNAL_NET_NAME},model=virtio,mac=${EXT_VM1_MAC}"

# wait dhcp for vm1
func_wait_dhcp "30"

func_deploy_vm ${VM2_NAME} ${VM2_HDD} ${VM2_CONFIG_ISO}

# debug
virsh list --all

exit 0
