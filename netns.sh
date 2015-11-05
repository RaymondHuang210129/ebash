#!/bin/bash

# Copyright 2015, SolidFire, Inc. All rights reserved.


NETNS_DIR="/run/netns"

#-------------------------------------------------------------------------------
# Idempotent create a network namespace
#
netns_create()
{
    $(declare_args ns_name)

    # Do not create if it already exists
    [[ -e "${NETNS_DIR}/${ns_name}" ]] && return 0

    ip netns add "${ns_name}"
    netns_exec "${ns_name}" ip link set dev lo up
}

#-------------------------------------------------------------------------------
# Idempotent delete a network namespace
#
netns_delete()
{
    $(declare_args ns_name)

    # Do not delete if it does not exist
    [[ ! -e "${NETNS_DIR}/${ns_name}" ]] && return 0

    netns_exec "${ns_name}" ip link set dev lo down
    ip netns delete "${ns_name}"
}

#-------------------------------------------------------------------------------
# Execute a command in the given network namespace
#
netns_exec()
{
    $(declare_args ns_name)
    ip netns exec "${ns_name}" "$@"
}

#-------------------------------------------------------------------------------
# Get a list of network namespaces
#
netns_list()
{
    ip netns list | sort
}

#-------------------------------------------------------------------------------
# Check if a network namespace exists
#
netns_exists()
{
    $(declare_args ns_name)
    [[ -e "${NETNS_DIR}/${ns_name}" ]] && return 0 || return 1
}

#-------------------------------------------------------------------------------
# create a pack containing the network namespace parameters
#
# Args: <netns pack name> <optional parameter pair list>
#
# ex: netns_init nsparams ns_name=mynamespace devname=mynamespace_eth0       \
#             peer_devname=eth0 connected_nic=eth0 bridge_cidr=<ipaddress>   \
#             nic_cidr=<ipaddress>
#
#  Where the options are:
#        ns_name        : The namespace name
#        devname        : veth pair's external dev name
#        peer_devname   : veth pair's internal dev name
#        connected_nic  : nic that can talk to the internet
#        bridge_cidr    : cidr for the bridge (ex: 1.2.3.4/24)
#        nic_cidr       : cidr for the internal nic (peer_devname)
#
netns_init()
{
    $(declare_args netns_args)

    pack_set ${netns_args}            \
        netns_args_name=${netns_args} \
        ns_name=                      \
        devname=                      \
        peer_devname=                 \
        connected_nic=                \
        bridge_cidr=                  \
        nic_cidr=                     \
        "${@}"

    return 0
}

#-------------------------------------------------------------------------------
# Ensure that the minimum parameters to set up a namespace are present in the pack
#    and that the parameters meet some minimum criteria in form and/or length
#
# Args: <netns pack name>
#
netns_check_pack()
{
    $(declare_args netns_args)

    local key
    for key in ns_name devname peer_devname connected_nic bridge_cidr nic_cidr ; do
        if ! pack_contains ${netns_args} ${key} ; then
            edebug "ERROR: netns_args key missing (${key})"
            pack_set $(pack_get ${netns_args} netns_args_name) API_Error_message="ERROR: netns_args key missing (${key})"
            return 1
        fi
    done

    $(pack_import ${netns_args} ns_name bridge_cidr nic_cidr)

    if [[ ${#ns_name} -gt 12 ]] ; then
        edebug "ERROR: namespace name too long (Max: 12 chars)"
        pack_set $(pack_get ${netns_args} netns_args_name) API_Error_message="ERROR: namespace name too long (Max: 12 chars)"
        return 1
    fi

    # a cidr is an ip address with the number of static (or network) bits 
    # added to the end.  It is typically of the form "A.B.C.D/##".  the "ip"
    # utility uses cidr addresses rather than netmasks, as they serve the same
    # purpose.  This regex ensures that the address is a cidr address.
    local cidr_regex="[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}"

    if ! [[ ${bridge_cidr} =~ ${cidr_regex} ]] ; then
        edebug "ERROR: bridge_cidr is wrong [${bridge_cidr}]"
        pack_set $(pack_get ${netns_args} netns_args_name) API_Error_message="ERROR: bridge_cidr is wrong [${bridge_cidr}]"
        return 1
    fi

    if ! [[ ${nic_cidr} =~ ${cidr_regex} ]] ; then
        edebug "ERROR: nic_cidr is wrong [${nic_cidr}]"
        pack_set $(pack_get ${netns_args} netns_args_name) API_Error_message="ERROR: nic_cidr is wrong [${nic_cidr}]"
        return 1
    fi
}

#-------------------------------------------------------------------------------
# Run a command in a netns chroot that already exists
#
# Args: <netns pack name> <chroot root dir> <command with args>
#
netns_chroot_exec()
{
    $(declare_args netns_args chroot_root)

    $(pack_import ${netns_args} ns_name)

    edebug "Executing command in namespace [${ns_name}] and chroot [${chroot_root}]: ${@}"
    netns_exec ${ns_name} chroot "${chroot_root}" "${@}"
}

#-------------------------------------------------------------------------------
# Set up the network inside a network namespace
#
# This will give you a network that can talk to the outside world from within
# the namespace
#
# Args: <netns pack name>
#
# Note: https://superuser.com/questions/764986/howto-setup-a-veth-virtual-network
#
netns_setup_connected_network()
{
    $(declare_args netns_args)

    netns_check_pack ${netns_args}

    $(pack_import ${netns_args})

    # this allows packets to come in on the real nic and be forwarded to the
    # virtual nic.  It turns on routing in the kernel.
    echo 1 > /proc/sys/net/ipv4/ip_forward

    $(tryrc netns_exists ${ns_name})
    if [[ ${rc} -eq 1 ]] ; then
        edebug "ERROR: namespace [${ns_name}] does not exist"
        return 1
    fi

    if [[ -L /sys/class/net/${devname} ]] ; then
        edebug "WARN: device (${devname}) already exists, returning"
        return 0
    fi

    # We create all the virtual things we need.  A veth pair, a tap adapter
    # and a virtual bridge
    ip link add dev ${devname} type veth peer name ${devname}p
    ip link set dev ${devname} up
    ip tuntap add ${ns_name}_t mode tap
    ip link set dev ${ns_name}_t up
    ip link add ${ns_name}_br type bridge

    # put the tap adapter in the bridge
    ip link set ${ns_name}_t master ${ns_name}_br

    # put one end of the veth pair in the bridge
    ip link set ${devname} master ${ns_name}_br

    # give the bridge a cidr address (a.b.c.d/##)
    ip addr add ${bridge_cidr} dev ${ns_name}_br

    # bring up the bridge
    ip link set ${ns_name}_br up

    # put the other end of the veth pair in the namespace
    ip link set ${devname}p netns ${ns_name}

    # and rename the nic in the namespace to what was specified in the args
    ip netns exec ${ns_name} ip link set dev ${devname}p name ${peer_devname}

    # Add iptables rules to allow the bridge and the connected nic to MASQARADE
    netns_add_iptables_rules ${ns_name} ${ns_name}_br ${connected_nic}

    #add the cidr address to the nic in the namespace
    ip netns exec ${ns_name} ip addr add ${nic_cidr} dev ${peer_devname}
    ip netns exec ${ns_name} ip link set dev ${peer_devname} up

    # Add a route so that the namespace can communicate out
    ip netns exec ${ns_name} ip route add default via ${bridge_cidr//\/[0-9]*/}

    #DNS is taken care of by the filesystem (either in a chroot or outside)
}

#-------------------------------------------------------------------------------
# Remove the namespace network
#
# Args: <netns pack name>
#
netns_remove_network()
{
    $(declare_args netns_args)

    netns_check_pack ${netns_args}

    $(pack_import ${netns_args} ns_name connected_nic)

    local device
    for device in /sys/class/net/${ns_name}* ; do
      if [[ -L ${device} ]] ; then
          local basename_device=$(basename ${device})
          ip link set ${basename_device} down
          ip link delete ${basename_device}
      fi
    done

    netns_remove_iptables_rules ${ns_name} ${ns_name}_br ${connected_nic}
}

#-------------------------------------------------------------------------------
# Add routing rules to the firewall to let traffic in/out of the namespace
#
# Args: <netns pack name> <additional targets to remove>
#
netns_add_iptables_rules()
{
    $(declare_args netns_args)

    netns_check_pack ${netns_args}

    $(pack_import ${netns_args} ns_name)

    local device
    for device in ${@} ; do
        $(tryrc netns_iptables_rule_exists ${ns_name} ${device})
        [[ ${rc} -eq 0 ]] && continue
        iptables -t nat -A POSTROUTING -o ${device} -j MASQUERADE
    done
}

#-------------------------------------------------------------------------------
# Remove routing rules added from above
#
# Args: <netns pack name> <device name>...
#
netns_remove_iptables_rules()
{
    $(declare_args netns_args)

    netns_check_pack ${netns_args}

    $(pack_import ${netns_args} ns_name)

    local device
    for device in ${@} ; do
        $(tryrc netns_iptables_rule_exists ${ns_name} ${device})
        [[ ${rc} -ne 0 ]] && continue
        iptables -t nat -D POSTROUTING -o ${device} -j MASQUERADE
    done
}

#-------------------------------------------------------------------------------
# Check if a rule exists for a given nic in the namespace
#
# Args: <netns pack name> <device name>
#
netns_iptables_rule_exists()
{
    $(declare_args netns_args devname)

    netns_check_pack ${netns_args}

    $(pack_import ${netns_args} ns_name)

    iptables -t nat -nvL           | \
      sed -n '/POSTROUTING/,/^$/p' | \
      grep -v "^$"                 | \
      tail -n -2                   | \
      grep -q ${devname}
}

