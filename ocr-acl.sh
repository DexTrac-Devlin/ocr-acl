#!/bin/bash
# Collect Database Variables
source $WORKINGDIR/envVars
# Collect Known Peers
PGPASSWORD="$PGPASSWORD" psql -U $PGUSERNAME -d $PGDATABASE -h $PGHOSTORIP -p 5432 -c '\copy (SELECT addr FROM p2p_peers) TO 'peer_ip_addrs' CSV;'
echo "Formatting Peer Information."
sed -i -e 's|/ip4/||g' peer_ip_addrs
sed -i 's|/dns4/.*||' peer_ip_addrs
sed -i 's|/tcp/|, |' peer_ip_addrs
sed -i '/^$/d' peer_ip_addrs
# Create whitelist for known ocr peers
while read ip port; do
    iptables -A INPUT -s $ip -p tcp --dport $LISTENPORT -j ACCEPT
done < "peer_ip_addrs"
iptables -A INPUT -p tcp --dport $LISTENPORT -j REJECT
# Dedupe rules
iptables-save | sort -u | uniq | iptables-restore
