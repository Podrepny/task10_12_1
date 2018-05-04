function func_gen_conf_ext {
cat <<EOF > ${EXT_XML_PATH}
<network>
  <name>${EXTERNAL_NET_NAME}</name>
  <forward mode='nat'/>
  <bridge name='${EXT_VIBR_NAME}' stp='on' delay='0'/>
  <ip address='${EXTERNAL_NET_HOST_IP}' netmask='${EXTERNAL_NET_MASK}'>
    <dhcp>
      <range start='${EXTERNAL_NET}.${EXT_DHCP_IP_RANGE_BEGIN}' end='${EXTERNAL_NET}.${EXT_DHCP_IP_RANGE_END}'/>
    </dhcp>
  </ip>
</network>
EOF
}

function func_gen_conf_int {
cat <<EOF > ${INT_XML_PATH}
<network>
  <name>${INTERNAL_NET_NAME}</name>
  <bridge name='${INT_VIBR_NAME}'/>
</network>
EOF
}

function func_gen_conf_mgm {
cat <<EOF > ${MGM_XML_PATH}
<network>
  <name>${MANAGEMENT_NET_NAME}</name>
  <bridge name='${MGM_VIBR_NAME}'/>
  <ip address="${MANAGEMENT_HOST_IP}" netmask="${MANAGEMENT_NET_MASK}"/>
</network>
EOF
}

function func_create_net {
  virsh net-define $2
  virsh net-autostart $1
  virsh net-start $1
}

function func_gen_cludinit_conf_vm1 {
  mkdir -p $1

## meta-data
cat <<EOF > $1/meta-data
instance-id: iid-$VM1_NAME
hostname: $VM1_NAME
local-hostname: $VM1_NAME
network-interfaces: |
  auto $VM1_EXTERNAL_IF
  iface $VM1_EXTERNAL_IF inet dhcp

  auto $VM1_INTERNAL_IF
  iface $VM1_INTERNAL_IF inet static
  address $VM1_INTERNAL_IP
  network $INTERNAL_NET_IP
  netmask $INTERNAL_NET_MASK

  auto $VM1_MANAGEMENT_IF
  iface $VM1_MANAGEMENT_IF inet static
  address $VM1_MANAGEMENT_IP
  network $MANAGEMENT_NET_IP
  netmask $MANAGEMENT_NET_MASK
EOF

## user-data
SSH_PUBLIC_KEY=`cat /home/alexey/.ssh/id_rsa.pub`

cat <<EOF > $1/user-data
#cloud-config
#password: qwerty
#chpasswd: { expire: False }
ssh_authorized_keys:
  - $SSH_PUBLIC_KEY

runcmd:
 - [ sh, -c, "/sbin/sysctl net.ipv4.ip_forward=1" ]
 - [ sh, -c, "/sbin/iptables -t nat -A POSTROUTING -s ${VM2_INTERNAL_IP} -o ${VM1_EXTERNAL_IF} -j MASQUERADE" ]
 - [ sh, -c, "/sbin/ip link add ${VXLAN_IF} type vxlan id ${VID} remote ${VM2_INTERNAL_IP} local ${VM1_INTERNAL_IP} dstport 4789" ]
 - [ sh, -c, "/sbin/ip link set ${VXLAN_IF} up" ]
 - [ sh, -c, "/sbin/ip addr add ${VXLAN_NET}.${VM1_INTERNAL_IP##*.}/24 dev $VXLAN_IF" ]
 - [ sh, -c, "/usr/bin/curl -fsSL https://download.docker.com/linux/ubuntu/gpg | /usr/bin/apt-key add -" ]
 - [ sh, -c, '/usr/bin/add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"' ]
 - [ sh, -c, "/usr/bin/apt-get update" ]
 - [ sh, -c, "/usr/bin/apt-get -y install docker-ce" ]
EOF
}

function func_gen_cludinit_conf_vm2 {
  mkdir -p $1

## meta-data
cat <<EOF > $1/meta-data
instance-id: iid-$VM2_NAME
hostname: $VM2_NAME
local-hostname: $VM2_NAME
network-interfaces: |
  auto $VM2_INTERNAL_IF
  iface $VM2_INTERNAL_IF inet static
  address $VM2_INTERNAL_IP
  network $INTERNAL_NET_IP
  netmask $INTERNAL_NET_MASK
  gateway $VM1_INTERNAL_IP
  dns-nameservers $VM_DNS

  auto ens4
  iface ens4 inet static
  address $VM2_MANAGEMENT_IP
  network $MANAGEMENT_NET_IP
  netmask $MANAGEMENT_NET_MASK
EOF

## user-data
SSH_PUBLIC_KEY=`cat /home/alexey/.ssh/id_rsa.pub`

cat <<EOF > $1/user-data
#cloud-config
#password: qwerty
#chpasswd: { expire: False }
ssh_authorized_keys:
  - $SSH_PUBLIC_KEY

runcmd:
 - [ sh, -c, "/sbin/ip link add ${VXLAN_IF} type vxlan id ${VID} remote ${VM1_INTERNAL_IP} local ${VM2_INTERNAL_IP} dstport 4789" ]
 - [ sh, -c, "/sbin/ip link set ${VXLAN_IF} up" ]
 - [ sh, -c, "/sbin/ip addr add ${VXLAN_NET}.${VM2_INTERNAL_IP##*.}/24 dev $VXLAN_IF" ]
 - [ sh, -c, "/usr/bin/curl -fsSL https://download.docker.com/linux/ubuntu/gpg | /usr/bin/apt-key add -" ]
 - [ sh, -c, '/usr/bin/add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"' ]
 - [ sh, -c, "/usr/bin/apt-get update" ]
 - [ sh, -c, "/usr/bin/apt-get -y install docker-ce" ]
EOF
}

function func_deploy_vm {
  local VM_NAME=$1
  local VM_HDD=$2
  local VM_HDD_DIR="${VM_HDD%\/*}"
  local VM_CONFIG_ISO=$3
  local EXTERNAL_NET=$4

  # Debug
  echo "VM_NAME: $VM_NAME"
  echo "VM_HDD: $VM_HDD"
  echo "VM_HDD_DIR: $VM_HDD_DIR"
  echo "VM_CONFIG_ISO: $VM_CONFIG_ISO"
  echo "EXTERNAL_NET: $EXTERNAL_NET"

  # Generate meta-data iso file
  mkdir -p $VM_HDD_DIR

  genisoimage -output $VM_CONFIG_ISO -volid cidata -joliet -input-charset utf-8 -rock $CLOUDINIT_CONF_DIR/$VM_NAME-config/{user-data,meta-data}

  qemu-img convert -O qcow2 xenial-server-cloudimg-amd64-disk1.img $VM_HDD

  # Create vm
  #virt-install --name $VM_NAME --ram 1024 --vcpus=2 --hvm --os-type=linux --os-variant=ubuntu16.04 --disk path=$VM_HDD,format=qcow2,bus=virtio,cache=none --disk path=$VM_CONFIG_ISO,device=cdrom $EXTERNAL_NET --network network=internal,model=virtio --network network=management,model=virtio --graphics vnc,port=-1,listen=0.0.0.0 --noautoconsole --virt-type kvm

  GENERIC_OPTS="--ram 1024 --vcpus=2 --hvm --os-type=linux --os-variant=ubuntu16.04 --graphics vnc,port=-1,listen=0.0.0.0 --noautoconsole --virt-type kvm"
  virt-install \
    $GENERIC_OPTS \
    --name $VM_NAME \
    --disk path=$VM_HDD,format=qcow2,bus=virtio,cache=none \
    --disk path=$VM_CONFIG_ISO,device=cdrom \
    $EXTERNAL_NET \
    --network network=$INTERNAL_NET_NAME,model=virtio \
    --network network=$MANAGEMENT_NET_NAME,model=virtio
}
