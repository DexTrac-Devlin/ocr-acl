#!/bin/bash
WORKING_DIR=$(pwd)

# Collect Database Variables
source $WORKING_DIR/envVars

# Collect Known Peers
PGPASSWORD=$PGPASSWORD psql -U $PGUSERNAME -d $PGDATABASE -h $PGHOSTORIP -p 5432 -c '\copy (SELECT addr FROM p2p_peers) TO 'peer_ip_addrs' CSV;'
echo "Formatting Peer Information."
sed -i -e 's|/ip4/||g' peer_ip_addrs
sed -i 's|/dns4/.*||' peer_ip_addrs
sed -i 's|/tcp/.*||' peer_ip_addrs
sed -i '/^$/d' peer_ip_addrs
sed -z -i 's/\n/,/g;s/,$/\n/' peer_ip_addrs

# Create whitelist for known ocr peers
while read ip port; do
aws ec2 authorize-security-group-ingress --group-id $EC2GROUP --protocol tcp --port $LISTENPORT --cidr $ip/32 >/dev/null 2>&1
done < "peer_ip_addrs"
