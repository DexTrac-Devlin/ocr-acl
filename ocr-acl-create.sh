#!/bin/bash

# Text Formatting
b=$(tput bold)
ub=$(tput sgr0)
un=$(tput smul)
nun=$(tput rmul)
blk_bg=$(tput setab 0)
blue_fg=$(tput setaf 6)
yellow_fg=$(tput setaf 3)
reset=$(tput sgr0)
WORKING_DIR=$(pwd)

# Check if root
if [ "$EUID" -ne 0 ]
  then echo "${b} Run as elevated user (sudo)${n}"
  exit
fi

# Check if running OS is Debian or RHEL based
if [ -f "/etc/debian_version" ]
then
   echo "Debian System Detected"
   deb_check=1
elif [ -f "/etc/redhat-release" ]
then
   echo "Red Hat System Detected"
   rhel_check=1
fi

# =========
# Install Dependencies
check_deb_deps () {
echo "---------"
echo "${blue_fg}Checking/Resolving dependencies.${reset}"

if ! dpkg -s postgresql-client >/dev/null 2>&1; then
    echo "Installing PostgreSQL Client."
    sudo apt update && sudo apt -y install postgresql-client;
fi
echo "${blue_fg}Dependencies resolved.${reset}"
}

check_rpm_deps () {
echo "---------"
echo "${blue_fg}Checking/Resolving dependencies.${reset}"

if ! psql --version >/dev/null 2>&1; then
    echo "Installing PostgreSQL Client."
    sudo yum clean metadata && sudo yum install -y postgresql;
fi
echo "${blue_fg}Dependencies resolved.${reset}"
}

# =========
# Select level of automation
select_automation () {
echo "---------"
echo "${blue_fg}Would you like to create a cron job to update the ACL every hour? ${reset}"
PS3="Please select 1, 2, or 3 from the above options: "
options=("Create a cron job." "Run once." "Quit/Cancel")
select opt in "${options[@]}"
do
    case $opt in
        "Create a cron job.")
            create_cron
            ;;
        "Run once.")
            run_once
            ;;
        "Quit/Cancel")
            break
            ;;
        *) echo "invalid option $REPLY";;
    esac
done
exit
}

# =========
# Collect Variables
collect_vars () {
echo "---------"
source envVars
#get hostname/ip
if [ -z ${PGHOSTORIP+x} ]; then
    read -e -p "${blue_fg}Host/IP of Database:${reset}" PGHOSTORIP
    else echo "PostgreSQL Hostname is set to '$PGHOSTORIP'";
fi
#get username
if [ -z ${PGUSERNAME+x} ]; then
    read -e -p "${blue_fg}PostgreSQL Username:${reset}" PGUSERNAME
    else echo "PostgreSQL Username is set to '$PGUSERNAME'";
fi
#get password
if [ -z ${PGPASSWORD+x} ]; then
    read -e -p "${blue_fg}PostgreSQL Password:${reset}" PGPASSWORD
    else echo "PostgreSQL Password is set to '$PGPASSWORD'";
fi
#get databse
if [ -z ${PGDATABASE+x} ]; then
    read -e -p "${blue_fg}PostgreSQL Database:${reset}" PGDATABASE
    else echo "PostgreSQL Database is set to '$PGDATABASE'";
fi
#get ocr listen port
if [ -z ${LISTENPORT+x} ]; then
    read -e -p "${blue_fg}OCR Node Listening Port:${reset}" LISTENPORT
    else echo "PostgreSQL Database is set to '$LISTENPORT'";
fi
echo ""
}

update_env_vars () {
sed -i "s|your_psql_host_/ip|$PGHOSTORIP|g" envVars
sed -i "s|your_psql_username|$PGUSERNAME|g" envVars
sed -i "s|your_psql_password|$PGPASSWORD|g" envVars
sed -i "s|your_psql_database|$PGDATABASE|g" envVars
sed -i "s|your_ocr_listenport|$LISTENPORT|g" envVars
sed -i "s|#PG|PG|g" envVars
sed -i "s|#LI|LI|g" envVars
}

# =========
# Collect Peer Information
collect_peers () {
echo "---------"
echo "Collecting Peer information."
PGPASSWORD="$PGPASSWORD" psql -U $PGUSERNAME -d $PGDATABASE -h $PGHOSTORIP -p 5432 -c '\copy (SELECT addr FROM p2p_peers) TO 'peer_ip_addrs' CSV;'
echo "Formatting Peer Information."
sed -i -e 's|/ip4/||g' peer_ip_addrs
sed -i 's|/dns4/.*||' peer_ip_addrs
sed -i 's|/tcp/|, |' peer_ip_addrs
sed -i '/^$/d' peer_ip_addrs
sed -z -i 's/\n/,/g;s/,$/\n/' peer_ip_addrs
}

# =========
# Create ip table Rules based on peer info
create_iptables_rules () {
while read ip port; do
    iptables -A INPUT -s $ip -p tcp --dport $LISTENPORT -j ACCEPT
done < "peer_ip_addrs"
iptables -A INPUT -p tcp --dport $LISTENPORT -j REJECT
}

# =========
# Create Bash Script for Automation Purposes
make_shell_script () {
sudo chmod +x $WORKING_DIR/ocr-acl.sh
}

# =========
# create cronjob to run the above script
add_to_crontab () {
(crontab -l 2>/dev/null; echo "0 * * * * $WORKING_DIR/ocr-acl.sh") | crontab -
}

# ==================
# =========
# Create Hourly cron Job
create_cron () {
collect_vars
update_env_vars
collect_peers
make_shell_script
add_to_crontab
exit
}

# =========
# Run Script Once
run_once () {
collect_vars
update_env_vars
collect_peers
create_iptables_rules
exit
}

# =========
# Install deps for selected OS
if [[ $deb_check == "1" ]]
then
   check_deb_deps
elif [[ $rhel_check == "1" ]]
then
   check_rpm_deps
else
   echo "Distribution check failed. Are you running something other than RHEL/Debian?"
fi
select_automation
