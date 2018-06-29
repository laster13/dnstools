#!/bin/sh

# Delete Let's encrypt validation code from DNSSEC zone
# v.20180325 2018 (c) Max Kostikov http://kostikov.co e-mail: max@kostikov.co
#

nsddir="/mnt/docker/nsd"

zone="${nsddir}/zones/db.${CERTBOT_DOMAIN}"

[ `grep "acme-challenge" $zone | wc -l` -eq 0 ] && exit

sed -i.bak '/^_acme-challenge/d' $zone

${nsddir}/dnsnewserial.sh $zone
docker exec nsd signzone $CERTBOT_DOMAIN
