#!/bin/bash

set -x
RUNTIME=${1:-rtpengine}

# Try to load kernel module (don't fail if it doesn't exist)
if lsmod | grep xt_RTPENGINE; then
	echo "rtpengine kernel module already loaded."
elif modprobe xt_RTPENGINE 2>/dev/null; then
	echo "rtpengine kernel module loaded successfully."
else
	echo "WARNING: rtpengine kernel module not available, using userspace forwarding (slower but functional)"
fi

# Populate options of the rtpengine cli command
[ -z "$INTERFACE" ] && INTERFACE="$(awk 'END{print $1}' /etc/hosts)"
[ -z "$TABLE" ] && TABLE="0"
[ -z "$LISTEN_NG" ] && LISTEN_NG="$(awk 'END{print $1}' /etc/hosts):2223"
[ -z "$PORT_MIN" ] && PORT_MIN="30000"
[ -z "$PORT_MAX" ] && PORT_MAX="40000"
[ -z "$TOS" ] && TOS="184"
[ -z "$PIDFILE" ] && PIDFILE="/run/ngcp-rtpengine-daemon.pid"

LISTEN_CLI="$(awk 'END{print $1}' /etc/hosts):9901"

OPTIONS=""
OPTIONS="$OPTIONS --interface=$INTERFACE --listen-ng=$LISTEN_NG --listen-cli=$LISTEN_CLI --pidfile=$PIDFILE --port-min=$PORT_MIN --port-max=$PORT_MAX "
OPTIONS="$OPTIONS --table=$TABLE  --tos=$TOS --foreground"

if test "$NO_FALLBACK" = "yes" ; then
	OPTIONS="$OPTIONS --no-fallback"
fi

set +e

# Only delete table if kernel module is available
if [ -e /proc/rtpengine/control ]; then
	echo "del $TABLE" > /proc/rtpengine/control 2>/dev/null
fi

# Setup IPv4 iptables
iptables -N rtpengine 2> /dev/null
iptables -D INPUT -j rtpengine 2> /dev/null
iptables -I INPUT -j rtpengine

# Only add RTPENGINE target if kernel module is available
if [ -e /proc/rtpengine/control ]; then
	iptables -D rtpengine -p udp -j RTPENGINE --id "$TABLE" 2>/dev/null
	iptables -I rtpengine -p udp -j RTPENGINE --id "$TABLE"
	echo "IPv4 kernel forwarding enabled"
else
	echo "Skipping RTPENGINE iptables target (kernel module not available)"
fi

iptables-save > /etc/iptables.rules

# Setup IPv6 iptables (with error handling)
echo "Setting up IPv6 tables..."
if ip6tables -N rtpengine 2> /dev/null; then
	ip6tables -D INPUT -j rtpengine 2> /dev/null
	ip6tables -I INPUT -j rtpengine
	
	# Only add RTPENGINE target if kernel module is available
	if [ -e /proc/rtpengine/control ]; then
		ip6tables -D rtpengine -p udp -j RTPENGINE --id "$TABLE" 2>/dev/null
		ip6tables -I rtpengine -p udp -j RTPENGINE --id "$TABLE" 2>/dev/null
		echo "IPv6 kernel forwarding enabled"
	fi
	
	ip6tables-save > /etc/ip6tables.rules 2>/dev/null
else
	echo "WARNING: IPv6 tables not available (this is OK, rtpengine will work with IPv4 only)"
fi

# Add static route only if UPF_IP is set (optional for VoLTE/EPC setups)
if [ ! -z "$UPF_IP" ]; then
	ip r add 192.168.101.0/24 via ${UPF_IP} 2>/dev/null || echo "Static route already exists or not needed"
fi

set -x

exec $RUNTIME $OPTIONS
