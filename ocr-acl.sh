#!/bin/bash
WORKING_DIR=$(pwd)

# Collect Database Variables
#PGHOSTORIP=your_psql_host_/ip
#PGUSERNAME=your_psql_username
#PGPASSWORD=your_psql_password
#PGDATABASE=your_psql_database
#LISTENPORT=your_ocr_listenport
source $WORKING_DIR/envVars

# Collect Known Peers
PGPASSWORD=$PGPASSWORD psql -U $PGUSERNAME -d $PGDATABASE -h $PGHOSTORIP -p 5432 -c '\copy (SELECT addr FROM p2p_peers) TO 'peer_ip_addrs' CSV;'
echo "Formatting Peer Information."
sed -i -e 's|/ip4/||g' peer_ip_addrs
sed -i 's|/dns4/.*||' peer_ip_addrs
sed -i 's|/tcp/.*||' peer_ip_addrs
sed -i '/^$/d' peer_ip_addrs
#sed -z -i 's/\n/,/g;s/,$/\n/' peer_ip_addrs

# Create whitelist for known ocr peers
peerips="$(< peer_ip_addrs)"
sudo iptables -A INPUT -s $peerips -p tcp --dport $LISTENPORT -j ACCEPT
sudo iptables -A INPUT -p tcp --dport $LISTENPORT -j REJECT
# Dedupe rules
sudo iptables-save | sort -u | uniq | sudo iptables-restore
