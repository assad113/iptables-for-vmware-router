# Log iptables related messages into separate log file
echo "IPTABLES_LOG=/var/log/iptables.log
:msg,contains,"FW-ACCEPT" $IPTABLES_LOG
:msg,contains,"FW-DROP" $IPTABLES_LOG
:msg,contains,"FW-REJECT" $IPTABLES_LOG" > /etc/rsyslog.d/80-iptables.conf

# Restart rsyslog
sudo systemctl restart rsyslog.service