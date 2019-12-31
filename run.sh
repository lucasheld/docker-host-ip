#!/bin/bash

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

# request bidge name
echo "[+] Enter your settings:"
while true
do
    read -p "New docker bridge name: " BRIDGE_NAME
    # check for empty value
    if [ ${#BRIDGE_NAME} -eq 0 ]
    then
        echo "Bridge name can not be empty"
        continue
    fi
    # check for max value length
    if [ ${#BRIDGE_NAME} -ge 15 ]
    then
        echo "Bridge name can not have more than 14 characters"
        continue
    fi
    # check if bridge already exists
    docker network ls | tail -n +2 | awk '{print $2}' | grep -q "^${BRIDGE_NAME}\$"
    if [ "${?}" -eq 0 ]
    then
        echo "Bridge name already used"
        continue
    fi
    break
done

# request interface name
while true
do
    read -p "Interface for outgoing connections: " INTERFACE_NAME
    # check if interface exists
    ip -4 addr show "${INTERFACE_NAME}" &> /dev/null
    if [ "${?}" -ne 0 ]
    then
        echo "Interface does not exists"
        continue
    fi
    break
done

# request interface dns
DEFAULT_INTERFACE_DNS="1.1.1.1"
read -p "Interface DNS Server [${DEFAULT_INTERFACE_DNS}]: " INTERFACE_DNS
INTERFACE_DNS="${INTERFACE_DNS:-${DEFAULT_INTERFACE_DNS}}"

# print settings
echo "[+] Using the following settings:"
echo "BRIDGE_NAME: ${BRIDGE_NAME}"
echo "INTERFACE_NAME: ${INTERFACE_NAME}"
echo "INTERFACE_DNS: ${INTERFACE_DNS}"

# create docker bridge
docker network create \
    --attachable \
    --opt "com.docker.network.bridge.enable_ip_masquerade=false" \
    --opt "com.docker.network.bridge.name=${BRIDGE_NAME}" \
    "${BRIDGE_NAME}" \
    > /dev/null
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
