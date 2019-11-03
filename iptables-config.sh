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
SOURCE_NETWORK="172.13.15.0/20"

### Custom config ###

# Linux repo (mirror.switch.ch)
LINUX_REPO="130.59.113.36"

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

# Accept all established or related inbound connections
$IPTABLES -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Accept all established or related outbound connections
$IPTABLES -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

### Custom rules ###

# Accept all inbound and outbound ICMP packets (e.g. ping)
$IPTABLES -A INPUT -i $BIND_INTERFACE -p icmp -j ACCEPT
$IPTABLES -A OUTPUT -o $BIND_INTERFACE -p icmp -j ACCEPT

# Accept incoming SSH connections only from a specific network
$IPTABLES -A INPUT -i $BIND_INTERFACE -p tcp -s $SOURCE_NETWORK --dport 22 -m state --state NEW,ESTABLISHED -j ACCEPT
$IPTABLES -A OUTPUT -o $BIND_INTERFACE -p tcp --sport 22 -m state --state ESTABLISHED -j ACCEPT

# Accept all outbound DNS connections
$IPTABLES -A OUTPUT -o $BIND_INTERFACE -p udp --dport 53 -j ACCEPT
$IPTABLES -A INPUT -i $BIND_INTERFACE -p udp --sport 53 -j ACCEPT

# Accept all outbound STMP connections
$IPTABLES -A OUTPUT -o $BIND_INTERFACE -p tcp --dport 25 -m state --state NEW,ESTABLISHED -j ACCEPT
$IPTABLES -A INPUT -i $BIND_INTERFACE -p tcp --sport 25 -m state --state ESTABLISHED -j ACCEPT

# Accept all outbound IMAP connections
$IPTABLES -A OUTPUT -o $BIND_INTERFACE -p tcp --dport 143 -m state --state NEW,ESTABLISHED -j ACCEPT
$IPTABLES -A INPUT -i $BIND_INTERFACE -p tcp --sport 143 -m state --state ESTABLISHED -j ACCEPT

# Accept explicit connections to required targets
$IPTABLES -A OUTPUT -o $BIND_INTERFACE -p tcp -d $LINUX_REPO --dport 80 -m state --state NEW,ESTABLISHED -j ACCEPT
$IPTABLES -A INPUT -i $BIND_INTERFACE -p tcp --sport 80 -m state --state ESTABLISHED -j ACCEPT

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