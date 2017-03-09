# Install iptables persistence package
sudo apt-get install iptables-persistent

# Log iptables related messages into separate log file
echo "# into separate file and stop their further processing
if  ($syslogfacility-text == 'kern') and \\
($msg contains 'IN=' and $msg contains 'OUT=') \\
then    -/var/log/iptables.log
    &   ~" > /etc/rsyslog.d/80-iptables.conf

# Restart rsyslog
sudo systemctl restart rsyslog.service

# Store the iptables config script locally and execute the same where iptables-persist will ensure the changes persist any reboot