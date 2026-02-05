#!/bin/bash


if [[ -z "$COMPONENT_NAME" ]]; then
	echo "Error: COMPONENT_NAME environment variable not set"; exit 1;
elif [[ "$COMPONENT_NAME" =~ ^(icscf-[[:digit:]]+$) ]]; then
	echo "Deploying component: '$COMPONENT_NAME'"
	/mnt/icscf/icscf_init.sh && \
	mkdir -p /var/run/kamailio_icscf && \
	kamailio -f /etc/kamailio_icscf/kamailio_icscf.cfg -P /kamailio_icscf.pid -DD -E -e
elif [[ "$COMPONENT_NAME" =~ ^(scscf-[[:digit:]]+$) ]]; then
	echo "Deploying component: '$COMPONENT_NAME'"
	/mnt/scscf/scscf_init.sh && \
	mkdir -p /var/run/kamailio_scscf && \
	kamailio -f /etc/kamailio_scscf/kamailio_scscf.cfg -P /kamailio_scscf.pid -DD -E -e
elif [[ "$COMPONENT_NAME" =~ ^(pcscf-[[:digit:]]+$) ]]; then
	echo "Deploying component: '$COMPONENT_NAME'"
	/mnt/pcscf/pcscf_init.sh && \
	mkdir -p /var/run/kamailio_pcscf && \
	kamailio -f /etc/kamailio_pcscf/kamailio_pcscf.cfg -P /kamailio_pcscf.pid -DD -E -e
else
	echo "Error: Invalid component name: '$COMPONENT_NAME'"
fi
