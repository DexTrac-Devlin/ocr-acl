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

## Prelimary Checks
# Check if root
if [ "$EUID" -ne 0 ]
  then echo "${b} Run as elevated user (sudo)${n}"
  exit
fi

# =========
## Functions

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

# Check if running in an EC2 instance
# Pulled from this link: https://serverfault.com/questions/462903/how-to-know-if-a-machine-is-an-ec2-instance
check_ec2(){
echo "----------"
echo "Checking if server is an EC2 instance."
echo "Please note that some of these checks have a chance of returning a false positive."

# This first, simple check will work for many older instance types.
if [ -f /sys/hypervisor/uuid ]; then
  # File should be readable by non-root users.
  if [ `head -c 3 /sys/hypervisor/uuid` == "ec2" ]; then
    echo "Older AWS EC2 Check Passed"
    aws_old_check=1
  else
    echo "System is not an older AWS EC2 instance"
  fi

# This check will work on newer m5/c5 instances, but only if you have root!
elif [ -r /sys/devices/virtual/dmi/id/product_uuid ]; then
  # If the file exists AND is readable by us, we can rely on it.
  if [ `head -c 3 /sys/devices/virtual/dmi/id/product_uuid` == "EC2" ]; then
    echo "AWS M5/C5 Check Passed"
    aws_m5_check=1
  else
    echo "System is not a newer AWS M5/C5 instance"
  fi

else
  # Fallback check of http://169.254.169.254/.
  if $(curl -s -m 5 http://169.254.169.254/latest/dynamic/instance-identity/document | grep -q availabilityZone) ; then
    echo "AWS Catchall Check Passed"
    aws_fallback_check=1
  else
    echo "AWS Catchall Check Failed"
  fi

fi
}

# Check if running OS is Debian or RHEL based
check_os(){
if [ -f "/etc/debian_version" ]
then
   echo "Debian System Detected"
   deb_check=1
elif [ -f "/etc/redhat-release" ]
then
   echo "Red Hat System Detected"
   rhel_check=1
fi
}

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

check_ec2_deps (){
echo "---------"
echo "${blue_fg}Checking/Resolving dependencies.${reset}"

if ! aws --version >/dev/null 2>&1; then
    echo "AWS CLI tool not installed."
    exit 1
fi
}

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
#optionally, get ec2 security group
if [ -z ${EC2_Group+x} ]; then
    read -e -p "${blue_fg}(Optional)EC2 Security Group:${reset}" EC2GROUP
    else echo "EC2 Security Group is set to '$EC2GROUP'";
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

# Create IPTables rules based on peer info
create_iptables_rules () {
while read ip port; do
    iptables -A INPUT -s $ip -p tcp --dport $LISTENPORT -j ACCEPT
done < "peer_ip_addrs"
iptables -A INPUT -p tcp --dport $LISTENPORT -j REJECT
}

# Create bash script for IPTables automation
iptables_shell_script () {
sudo chmod +x $WORKING_DIR/ocr-acl-iptables.sh
}

# Create cron job to run iptables script
iptables_crontab () {
(crontab -l 2>/dev/null; echo "Chainlink Firewall Script") | crontab -
(crontab -l 2>/dev/null; echo "0 * * * * $WORKING_DIR/ocr-acl-iptables.sh") | crontab -
(crontab -l 2>/dev/null; echo "") | crontab -
}

# Create EC2 rules based on peer info
create_ec2_rules () {
while read ip port; do 
aws ec2 authorize-security-group-ingress --group-id $EC2GROUP --protocol tcp --port $LISTENPORT --cidr $ip/32 >/dev/null 2>&1
done < "peer_ip_addrs"
}

# Create bash script for EC2 automation
ec2_shell_script () {
sudo chmod +x $WORKING_DIR/ocr-acl-ec2.sh
}

# Create cron job to run ec2 script
ec2_crontab () {
(crontab -l 2>/dev/null; echo "#Chainlink Firewall Script") | crontab -
(crontab -l 2>/dev/null; echo "0 * * * * $WORKING_DIR/ocr-acl-ec2.sh") | crontab -
(crontab -l 2>/dev/null; echo "") | crontab -
}

# Create Hourly cron Job
create_cron () {
collect_vars
update_env_vars
collect_peers
if [[ ! -z $deb_check || ! -z $rhel_check ]]
then
   iptables_shell_script
   iptables_crontab
else
   ec2_shell_script
   ec2_crontab
fi
exit
}

# Run Once
run_once () {
collect_vars
update_env_vars
collect_peers
if [[ ! -z $deb_check || ! -z $rhel_check ]]
then
   create_iptables_rules
else
   create_ec2_rules
fi
exit
}

# =========
## Work

# Run System Checks
check_ec2
# Run OS specific configs if not an EC2 instance
if [[ -z $aws_old_check && -z $aws_m5_check && -z $aws_fallback_check ]]
then
   check_os
   if [[ $deb_check == "1" ]]
   then
      check_deb_deps
   elif [[ $rhel_check == "1" ]]
   then
      check_rpm_deps
   else
      echo "Distribution check failed. Are you running something other than RHEL/Debian?"
      exit 1
   fi
else 
   check_ec2_deps
fi

## Run automation selection
select_automation
