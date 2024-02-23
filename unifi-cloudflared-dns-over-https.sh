#!/bin/bash
# Copyright 2024 breakerbar.com
# LICENSE Apache 2.0
# Project URL https://github.com/breakerbar/unifi-helpers

SERVICE_NAME=cloudflare-dns-proxy
UNIT_FILE="/etc/systemd/system/$SERVICE_NAME.service"

# if you have a Cloudflare Gateway DNS over HTTPS endpoint,
# export the variable in your env before running this script or 
# modify and uncomment the following line
#CLOUDFLARE_DNS_OVER_HTTPS_URL=https://xxxxxxxxxxx.cloudflare-gateway.com/dns-query

if [ "" == "$CLOUDFLARE_DNS_OVER_HTTPS_URL" ] ; then
    CLOUDFLARE_DNS_OVER_HTTPS_URL="https://cloudflare-dns.com/dns-query"
fi

if [ "11" == "$(lsb_release -rs)" ] ; then
    echo "Local UniFi OS is based on Debian Bullseye, continuing"
else
    echo "Local UniFi OS is not based on Debian Bullseye, exiting"
    exit 1
fi

# check if cloudflared already installed and if managed by apt/dpkg
if BIN_PATH=$(which cloudflared) ; then
    ERR="cloudflared is already installed"
    if CFD_REPO="$(dpkg -S "$(readlink -f "$BIN_PATH")" | cut -d ':' -f 1)" ; then
        ERR="$ERR and is managed by the $CFD_REPO repository"
    else
        ERR="$ERR and is not managed by any repository"
    fi
    ERR="$ERR, exiting"
    echo "$ERR"
    exit 1
fi

# check if cloudflared repo is already configured 
if CFD_REPO=$(grep -rhE "^deb.*pkg\.cloudflare\.com/cloudflared" /etc/apt/sources.list*) ; then
    echo "cloudflared apt repo already configured, skipping repo set up"
else
    # make sure we have a keyrings directory
    if [ ! -d /usr/share/keyrings ] ; then
        echo "keyrings directory missing, exiting"
        exit 1
    fi

    # if gpg key file already exists, move it out of the way
    if [ -e /usr/share/keyrings/cloudflare-main.gpg ] ; then
        echo "Moving keyring out of the way"
        mv -v /usr/share/keyrings/cloudflare-main.gpg "/usr/share/keyrings/cloudflare-main.gpg.$(date +%s)"
    fi

    # Add cloudflare gpg key
    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null

    # if repo list file already exists, move it out of the way
    if [ -e /etc/apt/sources.list.d/cloudflared.list ] ; then
        echo "Moving apt repo list file out of the way"
        mv -v /etc/apt/sources.list.d/cloudflared.list "/etc/apt/sources.list.d/cloudflared.list.$(date +%s).disabled"
    fi

    # Add this repo to your apt repositories
    echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared bullseye main' | tee /etc/apt/sources.list.d/cloudflared.list
fi
echo ""

# update repos
apt-get update 
echo ""

# install cloudflared, exit if failure
if ! apt-get install cloudflared -y ; then
    echo "error installing cloudflared package, exiting"
    exit 1
fi

# get path of cloudflared
BIN_PATH=$(which cloudflared)
if [ "" == "$BIN_PATH" ] ; then
    echo "Cannot find cloudflared executable, exiting"
    exit 1
fi

# test for presence of unit file
if [[ -e $UNIT_FILE ]] ; then
    echo "$UNIT_FILE already exists, skipping setup"
else
    if [ "" == "$CLOUDFLARE_DNS_OVER_HTTPS_URL" ] ; then
        CLOUDFLARE_DNS_OVER_HTTPS_URL="https://cloudflare-dns.com/dns-query"
        echo "Using default Cloudflare DoH endpoint."
    else
        echo "Using $CLOUDFLARE_DNS_OVER_HTTPS_URL as DoH endpoint."
    fi

    # write unit file
    cat << EOF > $UNIT_FILE
[Unit]
Description=cloudflared DNS proxy
After=network.target

[Service]
TimeoutStartSec=0
Type=Simple
ExecStart=$BIN_PATH proxy-dns --address 127.0.0.53 --upstream $CLOUDFLARE_DNS_OVER_HTTPS_URL
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

fi

# Service config instructions
cat << EOF

Install of cloudflared successful! 🎉

To finish configuration, do the following steps

1. Reload systemctl to pick up the new unit file
    systemctl daemon-reload

2. Start service now and run after system restart
    systemctl enable --now $SERVICE_NAME.service

EOF

exit 0


