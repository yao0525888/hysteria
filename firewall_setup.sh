#!/bin/bash

if [[ $EUID -ne 0 ]]; then
   echo "Error: This script must be run as root" 
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

ufw allow 7001:7006/tcp
ufw allow 7007:50000/tcp
ufw allow 7007:50000/udp

ufw --force enable

ufw status verbose