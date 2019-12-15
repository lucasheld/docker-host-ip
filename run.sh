#!/bin/bash
BRIDGE_NAME="br-rc-up"  # name of the new docker bridge, must be shorter than 15
INTERFACE_NAME="enp0s8"  # name of the interface which will be used for outgoing connections using the new bridge
INTERFACE_DNS="1.1.1.1"  # interface dns server


create_routing_table_enty() {
    # check if table already contains bridge
    grep -q " ${BRIDGE_NAME}$" /etc/iproute2/rt_tables
    if [ "${?}" -eq 0 ]
    then
        echo "reusing existing routing table entry"
        return
    fi
    # find unused table number
    for ((i=1; i<=2**31; i++))
    do
        grep -q "^${i} " /etc/iproute2/rt_tables
        TABLE_NAME="${?}"  # 0 if number found in table
        TABLE_RULES=$(sudo ip route list tab "${i}" | wc -l)  # 0 if no roules found for table
        if [ "${TABLE_NAME}" -ne 0 ] && [ "${TABLE_RULES}" -eq 0 ]
        then
            echo "${i} ${BRIDGE_NAME}" | sudo tee -a /etc/iproute2/rt_tables > /dev/null
            echo "created new routing table entry"
            return
        fi
    done
    echo "there is no free table number"
    exit 1
}

# create docker bridge
docker network create \
    --attachable \
    --opt "com.docker.network.bridge.enable_ip_masquerade=false" \
    --opt "com.docker.network.bridge.name=${BRIDGE_NAME}" \
    "${BRIDGE_NAME}"
BRIDGE_SUBNET=$(docker network inspect "${BRIDGE_NAME}" | grep -oP '(?<="Subnet": ")\d+.\d+.\d+.\d+\/\d+(?=")')
echo "created new docker bridge \"${BRIDGE_NAME}\" with subnet \"${BRIDGE_SUBNET}\""

# create routes and rules
create_routing_table_enty
INTERFACE_IP=$(ip -4 addr show "${INTERFACE_NAME}" | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
INTERFACE_GATEWAY=$(echo "${INTERFACE_IP%.*}.1")
sudo ip route add "${BRIDGE_SUBNET}" dev "${INTERFACE_NAME}" tab "${BRIDGE_NAME}"
sudo ip route add default via "${INTERFACE_GATEWAY}" dev "${INTERFACE_NAME}" tab "${BRIDGE_NAME}"
sudo ip rule add from "${BRIDGE_SUBNET}" tab "${BRIDGE_NAME}"
sudo ip route flush cache
sudo iptables  -t nat -A POSTROUTING -s "${BRIDGE_SUBNET}" ! -o "${BRIDGE_NAME}" -j SNAT --to-source "${INTERFACE_IP}"
echo "created routes from bridge \"${BRIDGE_NAME}\" to interface \"${INTERFACE_NAME}\""

# check ip address with and without new docker bridge
IP=$(docker run --rm byrnedo/alpine-curl -sS https://checkip.amazonaws.com)
echo "IP address used by default docker bridge: ${IP}"
IP=$(docker run --rm --network "${BRIDGE_NAME}" --dns="${INTERFACE_DNS}" byrnedo/alpine-curl -sS https://checkip.amazonaws.com)
echo "IP address used by docker bridge \"${BRIDGE_NAME}\": ${IP}"
