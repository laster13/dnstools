#!/bin/bash

function install_traefik() {
	echo -e "${BLUE}### TRAEFIK ###${NC}"

	TRAEFIK="$CONFDIR/docker/traefik"
	INSTALLEDFILE="$CONFDIR/resume"

	if [[ ! -f "$INSTALLEDFILE" ]]; then
	touch $INSTALLEDFILE> /dev/null 2>&1
	fi

	if docker ps | grep -q traefik; then
		echo -e " ${YELLOW}* Traefik est déjà installé !${NC}"
	else
		echo -e " ${BWHITE}* Installation Traefik${NC}"
		mkdir -p $TRAEFIK
		cp "$BASEDIR/includes/dockerapps/traefik.toml" "$CONFDIR/docker/traefik/"
		cp "$BASEDIR/includes/dockerapps/traefik.yml" "/tmp/"
		cp "$BASEDIR/includes/dockerapps/acme.json" "/tmp/"
		sed -i "s|%EMAIL%|$CONTACTEMAIL|g" $CONFDIR/docker/traefik/traefik.toml
		sed -i "s|%DOMAIN%|$DOMAIN|g" $CONFDIR/docker/traefik/traefik.toml
		sed -i "s|%DOMAIN%|$DOMAIN|g" /tmp/traefik.yml
		cd /tmp
		docker network create traefik_proxy > /dev/null 2>&1
		ansible-playbook traefik.yml
		rm traefik.yml acme.json
		echo "traefik-port-traefik.$DOMAIN" >> $INSTALLEDFILE
		checking_errors $?		
	fi
	echo ""
}

