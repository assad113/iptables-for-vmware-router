#!/bin/sh

# Abort script when command exits with error
set -e

# Print each command before it is executed (only for debugging)
#set -x

########################################################################
# Config
########################################################################

IPTABLES=$(which iptables)
IPTABLES_SAVE=$(which iptables-save)
IPTABLES_FILE="/etc/iptables/rules.v4"
MODPROBE=$(which modprobe)

BIND_INTERFACE=$(route | grep '^default' | grep -o '[^ ]*$')
INT_INTERFACE1=
INT_INTERFACE2=

# White listed Clumio source IP address
SOURCE_NETWORK="172.13.15.0/20"

#
VMWARE_CLUSTER_PUBLIC_IP="130.59.113.36"

########################################################################
# Saving Current firewall Rules
########################################################################

printf "Saving current firewall Rules ...\n"
$IPTABLES_SAVE > /root/iptables-works-`date +%F`
#If you do something that prevents your system from working, you can quickly restore it: iptables-restore < /root/iptables-works-2018-09-11

########################################################################
# Initialize firewall
########################################################################

printf "Initializing firewall ...\n"
printf "Using bind interface: $BIND_INTERFACE \n"
printf "Using source network: $SOURCE_NETWORK \n"

# Flush all chains
$IPTABLES -t filter -F
$IPTABLES -t nat -F
$IPTABLES -t mangle -F
$IPTABLES -t raw -F

# Delete all user defined chains
$IPTABLES -t filter -X
$IPTABLES -t nat -X
$IPTABLES -t mangle -X
$IPTABLES -t raw -X

# Zero the packet and byte counters in all chains
$IPTABLES -t filter -Z
$IPTABLES -t nat -Z
$IPTABLES -t mangle -Z
$IPTABLES -t raw -Z

# Setup default chain policies (drop everything by default)
$IPTABLES -P INPUT DROP
$IPTABLES -P FORWARD DROP
$IPTABLES -P OUTPUT DROP

# Setup policies for filter table (drop everything by default)
$IPTABLES -t filter -P INPUT DROP
$IPTABLES -t filter -P OUTPUT DROP
$IPTABLES -t filter -P FORWARD DROP

# Setup policies for nat table
$IPTABLES -t nat -P PREROUTING ACCEPT
$IPTABLES -t nat -P INPUT ACCEPT
$IPTABLES -t nat -P OUTPUT ACCEPT
$IPTABLES -t nat -P POSTROUTING ACCEPT

# Setup policies for mangle table
$IPTABLES -t mangle -P PREROUTING ACCEPT
$IPTABLES -t mangle -P INPUT ACCEPT
$IPTABLES -t mangle -P FORWARD ACCEPT
$IPTABLES -t mangle -P OUTPUT ACCEPT
$IPTABLES -t mangle -P POSTROUTING ACCEPT

# Setup policies for raw table
$IPTABLES -t raw -P PREROUTING ACCEPT
$IPTABLES -t raw -P OUTPUT ACCEPT

# Create user defined chains LOGACCEPT, LOGDROP and LOGREJECT
$IPTABLES -t filter -N LOGACCEPT
$IPTABLES -t filter -N LOGDROP
$IPTABLES -t filter -N LOGREJECT

# Setup LOGACCEPT chain
$IPTABLES -A LOGACCEPT -m limit --limit 10/minute -j LOG --log-prefix "FW-ACCEPT: "
$IPTABLES -A LOGACCEPT -j ACCEPT

# Setup LOGDROP chain
$IPTABLES -A LOGDROP -m limit --limit 10/minute -j LOG --log-prefix "FW-DROP: "
$IPTABLES -A LOGDROP -j DROP

# Setup LOGREJECT chain
$IPTABLES -A LOGREJECT -m limit --limit 10/minute -j LOG --log-prefix "FW-REJECT: "
$IPTABLES -A LOGREJECT -j REJECT

printf "Done initializing!\n"

########################################################################
# Setup firewall rules
########################################################################
# If you want packets logged use the target LOGDROP (-j LOGDROP)
# for logging and dropping the matching packet, LOGACCEPT (-j LOGACCEPT)
# for logging and accepting the matching packet, or LOGREJECT
# (-j LOGREJECT) for logging and rejecting the matching packet.
########################################################################

printf "Setting up firewall rules ...\n"

### Basic rules ###

# Accept all loopback traffic
$IPTABLES -A INPUT -i lo -j ACCEPT
$IPTABLES -A OUTPUT -o lo -j ACCEPT

# Accept all traffic from internal Interfaces
$IPTABLES -A INPUT -i INT_INTERFACE1 -j ACCEPT
$IPTABLES -A OUTPUT -o INT_INTERFACE1 -j ACCEPT
$IPTABLES -A INPUT -i INT_INTERFACE2 -j ACCEPT
$IPTABLES -A OUTPUT -o INT_INTERFACE2 -j ACCEPT

# Accept all established or related inbound connections
$IPTABLES -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Accept all established or related outbound connections
$IPTABLES -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

### Custom rules ###

# Accept all inbound and outbound ICMP packets (e.g. ping)
$IPTABLES -A INPUT -i $BIND_INTERFACE -p icmp -j ACCEPT
$IPTABLES -A OUTPUT -o $BIND_INTERFACE -p icmp -j ACCEPT
$IPTABLES -A FORWARD -p icmp -j ACCEPT

# Accept incoming connections only from a White listed Clumio Source IP
$IPTABLES -A INPUT -i $BIND_INTERFACE -p tcp -s $SOURCE_NETWORK -m state --state NEW,ESTABLISHED -j ACCEPT
$IPTABLES -A OUTPUT -o $BIND_INTERFACE -p tcp -m state --state ESTABLISHED -j ACCEPT
$IPTABLES -A FORWARD -i $BIND_INTERFACE -p tcp -s $SOURCE_NETWORK -m state --state NEW,ESTABLISHED -j ACCEPT
$IPTABLES -A FORWARD -o $BIND_INTERFACE -m state --state NEW,ESTABLISHED -j ACCEPT
$IPTABLES -A FORWARD -m conntrack --ctstate INVALID -j DROP

# Accept all outbound DNS connections
$IPTABLES -A OUTPUT -o $BIND_INTERFACE -p udp --dport 53 -j ACCEPT
$IPTABLES -A INPUT -i $BIND_INTERFACE -p udp --sport 53 -j ACCEPT
# for VPN
$IPTABLES -A INPUT -p udp -m multiport --dports 500,4500 -j ACCEPT
$IPTABLES -A INPUT -p udp -m udp --dport 1701 -m policy --dir in --pol ipsec -j ACCEPT
$IPTABLES -A FORWARD -i bond0 -o ppp+ -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
$IPTABLES -A FORWARD -i ppp+ -o bond0 -j ACCEPT
$IPTABLES -A FORWARD -s 192.168.42.0/24 -d 192.168.42.0/24 -i ppp+ -o ppp+ -j ACCEPT
$IPTABLES -A FORWARD -d 192.168.43.0/24 -i bond0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
$IPTABLES -A FORWARD -s 192.168.43.0/24 -o bond0 -j ACCEPT

# Accept explicit connections to required targets
#$IPTABLES -A OUTPUT -o $BIND_INTERFACE -p tcp -d $VMWARE_CLUSTER_PUBLIC_IP --dport 80 -m state --state NEW,ESTABLISHED -j ACCEPT
#$IPTABLES -A INPUT -i $BIND_INTERFACE -p tcp --sport 80 -m state --state ESTABLISHED -j ACCEPT

printf "Firewall is now configured and active!\n"

########################################################################
# Audit Logging
########################################################################

$IPTABLES -N LOGGING
$IPTABLES -A INPUT -j LOGGING
$IPTABLES -A OUTPUT -j LOGGING
$IPTABLES -A LOGGING -m limit --limit 10/minute -j LOG --log-prefix "FW-DROP: "
$IPTABLES -A LOGGING -j DROP

########################################################################
# Display configuration (optional)
########################################################################

#printf "Displaying current firewall configuration ...\n"

#printf "\nContent of filter table:\n\n"
#$IPTABLES -nvL -t filter

#printf "\nContent of nat table:\n\n"
#$IPTABLES -nvL -t nat

#printf "\nContent of mangle table:\n\n"
#$IPTABLES -nvL -t mangle

#printf "\nContent of raw table:\n\n"
#$IPTABLES -nvL -t raw

#printf "\n"

printf "Persisting current iptables: $IPTABLES_FILE\n"
$IPTABLES_SAVE > $IPTABLES_FILE

exit 0
