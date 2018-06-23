#!/bin/sh

# Add Let's encrypt validation code to DNSSEC zone
# v.20180325 2018 (c) Max Kostikov http://kostikov.co e-mail: max@kostikov.co
#

nsddir="/mnt/docker/nsd"

maindom=`echo $CERTBOT_DOMAIN | sed -r 's/.*\.([^.]+\.[^.]+)$/\1/'`
subdom=`echo $CERTBOT_DOMAIN | sed -r 's/(.+)\.[^.]+\.[^.]+$/\1/'`

if [ "$maindom" = "$subdom" ]
then
        str="_acme-challenge    IN TXT \"$CERTBOT_VALIDATION\""
else
        str="_acme-challenge.$subdom    IN TXT \"$CERTBOT_VALIDATION\""
fi

zone="${nsddir}/zones/db.${maindom}"
echo $str >> $zone

${nsddir}/dnsnewserial.sh $zone

docker exec -ti nsd nsd-control reload $maindom

sleep 10
