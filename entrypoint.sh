#!/bin/bash

set -e
echo "server"
/server &

python /patch-vpn-config.py --config /vpn.conf > /vpn.conf-fixed
cp /vpn.{conf-fixed,modified.conf}

sed -i '/^auth-user-pass.*$/d' /vpn.modified.conf
sed -i '/^auth-federate.*$/d' /vpn.modified.conf
sed -i '/^auth-retry.*$/d' /vpn.modified.conf

echo "" >> /vpn.modified.conf
echo "script-security 2" >> /vpn.modified.conf
echo "up /etc/openvpn/scripts/update-resolv-conf" >> /vpn.modified.conf
echo "down /etc/openvpn/scripts/update-resolv-conf" >> /vpn.modified.conf

VPN_HOST=$(cat /vpn.modified.conf | grep 'remote ' | cut -d ' ' -f2)
PORT=$(cat /vpn.modified.conf | grep 'remote ' | cut -d ' ' -f3)
PROTO=$(cat /vpn.modified.conf | grep "proto " | cut -d " " -f2)

echo "Connecting to $VPN_HOST on port $PORT/$PROTO"
wait_file() {
  local file="$1"; shift
  local wait_seconds="${1:-300}"; shift # 300 seconds as default timeout
  until test $((wait_seconds--)) -eq 0 -o -f "$file" ; do sleep 1; done
  ((++wait_seconds))
}

# create random hostname prefix for the vpn gw
RAND=$(openssl rand -hex 12)

# resolv manually hostname to IP, as we have to keep persistent ip address
SRV=$(dig a +short "${RAND}.${VPN_HOST}"|head -n1)
sed -i '/^remote .*$/d' /vpn.modified.conf
sed -i '/^remote-random-hostname.*$/d' /vpn.modified.conf

# cleanup
rm -f saml-response.txt
echo "Getting SAML redirect URL from the AUTH_FAILED response (host: ${SRV}:${PORT})..."
OVPN_OUT=$(/openvpn --config /vpn.modified.conf --verb 3 \
     --proto "$PROTO" --remote "${SRV}" "${PORT}" \
     --auth-user-pass <( printf "%s\n%s\n" "N/A" "ACS::35001" ) \
    2>&1 | grep AUTH_FAILED,CRV1)
echo $OVPN_OUT

URL=$(echo "$OVPN_OUT" | grep -Eo 'https://.+')
echo ""
echo ""
echo "Open this URL in your browser and log in (ctrl + click):"
echo ""
echo ""
echo $URL
sleep 1
wait_file "saml-response.txt" 300 || {
  echo "SAML Authentication timed out"
  exit 1
}

# get SID from the reply
VPN_SID=$(echo "$OVPN_OUT" | awk -F : '{print $7}')

echo "Running OpenVPN."

# Finally OpenVPN with a SAML response we got
# Delete saml-response.txt after connect
exec /openvpn --config /vpn.modified.conf \
              --verb 3 --auth-nocache --inactive 3600 \
              --proto $PROTO --remote $SRV $PORT \
              --script-security 2 \
              --route-up '/bin/rm saml-response.txt' \
              --auth-user-pass <( printf "%s\n%s\n" "N/A" "CRV1::${VPN_SID}::$(cat saml-response.txt)" )
