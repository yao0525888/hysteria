#!/bin/bash

exec > /dev/null 2>&1

if [[ $EUID -ne 0 ]]; then
   exit 1
fi

if ! command -v curl &> /dev/null; then
    apt-get update
    apt-get install curl -y
fi

PUBLIC_IP=$(curl -s icanhazip.com)

if [[ -z "$PUBLIC_IP" ]]; then
    exit 1
fi

if ! command -v ufw &> /dev/null; then
    apt-get update
    apt-get install ufw -y
fi

ufw --force reset

ufw default deny incoming
ufw default allow outgoing

ufw allow 22/tcp

ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 443/udp
ufw allow 8443/tcp
ufw allow 8443/udp

ufw allow from $PUBLIC_IP to any port 7001:7006 proto tcp
ufw allow 7007:50000/tcp
ufw allow 7007:50000/udp

ufw --force enable
