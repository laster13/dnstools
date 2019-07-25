#!/bin/bash

BASEDIR="/opt/seedbox-compose"
CONFDIR="/opt/seedbox"
SERVICESAVAILABLE="$BASEDIR/includes/config/services-available"
MEDIAVAILABLE="$BASEDIR/includes/config/media-available"
SERVICES="$BASEDIR/includes/config/services"
SERVICESUSER="/opt/seedbox/services-"
MEDIASUSER="/opt/seedbox/media-"
FILEPORTPATH="/opt/seedbox/ports.pt"
FILEPORTPATH1="/opt/seedbox/ports1.pt"
FILEPORTPATH2="/opt/seedbox/ports2.pt"
SCANPORTPATH="/opt/seedbox/scan.pt"
PLEXPORTPATH="/opt/seedbox/plex.pt"
PACKAGESFILE="$BASEDIR/includes/config/packages"
USERSFILE="/opt/seedbox/users"
GROUPFILE="/opt/seedbox/group"

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

function install_ansible() {
	## installation ansible
	echo -e "${BLUE}### ANSIBLE ###${NC}"
	echo -e " ${BWHITE}* Installation de Ansible ${NC}"
	apt-get install software-properties-common -y > /dev/null 2>&1
	apt-add-repository --yes --update ppa:ansible/ansible > /dev/null 2>&1
	apt-get install ansible -y > /dev/null 2>&1

	# Configuration ansible
 	mkdir -p /etc/ansible/inventories/ 1>/dev/null 2>&1
  	echo "[local]" > /etc/ansible/inventories/local
  	echo "127.0.0.1 ansible_connection=local" >> /etc/ansible/inventories/local

  	### Reference: https://docs.ansible.com/ansible/2.4/intro_configuration.html
  	echo "[defaults]" > /etc/ansible/ansible.cfg
  	echo "command_warnings = False" >> /etc/ansible/ansible.cfg
  	echo "callback_whitelist = profile_tasks" >> /etc/ansible/ansible.cfg
	echo "deprecation_warnings=False" >> /etc/ansible/ansible.cfg
  	echo "inventory = /etc/ansible/inventories/local" >> /etc/ansible/ansible.cfg
	checking_errors $?
}

function checking_errors() {
	if [[ "$1" == "0" ]]; then
		echo -e "	${GREEN}--> Operation success !${NC}"
	else
		echo -e "	${RED}--> Operation failed !${NC}"
	fi
}

	echo -e " ${BWHITE}* Mise à jour du git${NC}"
	cd /opt
	rm -rf seedbox-compose
	git clone https://github.com/laster13/patxav.git /opt/seedbox-compose > /dev/null 2>&1
	checking_errors $?

	echo -e " ${BWHITE}* Supression traefik${NC}"
	docker rm -f proxy_traefik > /dev/null 2>&1
	rm -rf /opt/seedbox/docker/traefik > /dev/null 2>&1
	checking_errors $?
	
	
