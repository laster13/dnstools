#!/bin/bash

## Script for automatically changing DANE TLSA hashes, after auto renewing Letsencrypt certificates 
## Version: 20180617 

#### LICENSE INFORMATION
## Copyright 2018 Dennis Baaten (Baaten ICT Security) 
##
## Licensed under the Apache License, Version 2.0 (the "License");
## you may not use this file except in compliance with the License.
## You may obtain a copy of the License at
##
##    http://www.apache.org/licenses/LICENSE-2.0
##
## Unless required by applicable law or agreed to in writing, software
## distributed under the License is distributed on an "AS IS" BASIS,
## WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
## See the License for the specific language governing permissions and
## limitations under the License.

#### ASSUMPTIONS WHILE MAKING THIS SCRIPT
## This script should be run every hour using cron 
## There is a DANE record present in the DNS zone (from the initial setup).
## Using NSD as a DNS server
## Root domain and www subdomain have the same certificate
## Zonefile does only contain DANE hash for root domain and www subdomain
## Default TLSA 1 0 1 is being used for all domains; being respectively the certificate usage field, the selector field, matching type field.

#### VERSION HISTORY
##
## Version 20180615
## - first release.
##
## Version 20180617
## - fixed a bug where not all domains were processed.
## - only replace DANE hashes with certificate usage 1. As a result trusted CA DANE records (usage type 3) are not affected.
## - added print status to stdout.
## 

#### SCRIPT START

## Create file with the bare domainnames
certbot certificates | grep "Domains:" | sed -e 's/^[ \t]*//' | cut -f1 --complement -d " " | tr " " "\n" > /etc/letsencrypt/letsencryptdomains
sed -i "/www/d" /etc/letsencrypt/letsencryptdomains
sed -i "2d" /etc/letsencrypt/letsencryptdomains

for domainname in $(cat /etc/letsencrypt/letsencryptdomains)
do
  #### First let's set some variables

  ## The current unix time (number of seconds since 1-1-1970)
  current_epoch="$(exec date '+%s')"
  ## The unix time of the last known modify date of the letsencrypt certificate file
  cert_file_renewal_date="$(exec stat $(readlink -f /etc/letsencrypt/live/$domainname/cert.pem) | grep Modif | cut -f1 --complement -d " " | sed 's/^[ \t]*//;s/[ \t]*$//')"
  cert_file_renewal_epoch="$(date --date="$cert_file_renewal_date" +"%s")"
  ## Set full filename path using know directory structure and zonefile naming convention
  filename="/mnt/docker/nsd/zones/db.$domainname"
  nsddir="/mnt/docker/nsd"
  ## Get dane hash from zonefile
  danezone=$(exec cat $filename | grep "TLSA" | cut -d " " -f7 | xargs)
  ## Calculate dane SHA256 hash based on the Letsencrypt certificate
  openssloutput=$(openssl x509 -in /etc/letsencrypt/live/$domainname/cert.pem -outform DER | openssl sha256)
  ## Get DANE hash from openssl output
  danecert=$(exec echo $openssloutput | cut -f2 -d "=" | xargs)
  
  ## Now, let's check if certbot renewal (which is run every 12 hours on my Debian server) has resulted in a new certficate in the past hour
  if (( $current_epoch - $cert_file_renewal_epoch < 3600  )); then
    ## Certbot has renewed the certificate less than an hour ago; add DANE hash of new certificate to DNS zonefile

        	## Check if the DANE hash from the new certificate ($danecert) already exists in the zone file.
        	## If there are multiple DANE hashes for the root domain in the file, $danezone contains all hashes seperated by a single space
        	if [[ "$danezone" =~ .*$danecert.* ]]; then
                	## DANE hash already exists in the zone file
      ## Maybe this script is rerun for another domain and no action should be taken for the current domain
      ## Maybe you reused a key-pair

      ## Print status to stdout
                	echo [$domainname] DANE hash from new certificate already exists in zonefile
        	else
                  ## Find the lines for DANE and add a new DANE record.
      ## What I actually do: I replace the old DANE record with the old DANE record including a comment followed by a DANE record on a new line.
      ## I also only replace DANE records with certificate usage field '1'. That's how I make sure that the roll over DANE records (which have usage field '3') are left intact. 
                  sed -i "/_dane IN TLSA 3/c\_dane IN TLSA 3 0 1 $danezone ; old-dane-hash\n_dane IN TLSA 3 0 1 $danecert" $filename
                  ${nsddir}/dnsnewserial.sh $filename
                  docker exec -ti nsd signzone $domainname [YYYYMMDDhhmmss]
                  docker exec -ti nsd nsd-control reload $domainname
      ## Print status to stdout
      echo [$domainname] Added new DANE hash in zonefile
      
    fi
  else
    ## Certificate was not renewed in the past hour (remember: this script should run every hour).
    ## Now I check if the certficate file is between 24 hours and 25 hours old. If that's the case then this means that the certificate was recently replaced and added to the DNS zone. 
    ## In my case 24 hours is more than enough time for the changed DNS zone (with the new DANE record) to spread over the internet. So after 24 hours, I activate the new certificate in apache and remove old certificate info from DNS zonefile
    if (( $current_epoch - $cert_file_renewal_epoch > 86400 )) && (( $current_epoch - $cert_file_renewal_epoch < 90000 )); then
      ## Check if the value 'old-dane-hash' exists in the zonefile
      if grep -qF old-dane-hash $filename; then
        ## Old DANE hashes exist in the zonefile; remove lines ending with the comment 'old-dane-hash'
        sed -i "/old-dane-hash/d" $filename
        ${nsddir}/dnsnewserial.sh $filename
        docker exec -ti nsd signzone $domainname [YYYYMMDDhhmmss]
        docker exec -ti nsd nsd-control reload $domainname
        service nginx restart
                              else
                                ## No old DANE hashes exist in file; stop script and do nothing
        ## Maybe this domain was already processed in a previous run of this script

        ## Print status to stdout
        echo [$domainname] no old DANE hash found in zonefile
                        fi

    else
      if (( $current_epoch - $cert_file_renewal_epoch > 90000 )); then
        ## Do nothing, all done

        ## Print status to stdout
        echo [$domainname] The latest certificate file is over 25 hours old and not processed
      else
        ## The 24 hour wait required for DNS changes to spread across the internet, is not yet over. Be patient.

        ## Print status to stdout
        echo [$domainname] Be patient and wait at least 24 hours for the DNS changed to spread across the internet
      fi
    fi
  fi
done
