#!/bin/bash -xv


#### SCRIPT START

## Create file with the bare domainnames
/opt/eff.org/certbot/venv/bin/certbot certificates | grep "Domains:" | sed -e 's/^[ \t]*//' | cut -f1 --complement -d " " | tr " " "\n" > /etc/letsencrypt/letsencryptdomains
sed -i "/www/d" /etc/letsencrypt/letsencryptdomains
sed -i "2d" /etc/letsencrypt/letsencryptdomains

for domainname in $(cat /etc/letsencrypt/letsencryptdomains)
do
  #### First let's set some variables

  ## The current unix time (number of seconds since 1-1-1970)
        current_epoch="$(exec date '+%s')"
  ## The unix time of the last known modify date of the letsencrypt certificate file
  cert_file_renewal_date="$(exec stat $(readlink -f /etc/letsencrypt/live/$domainname/cert.pem) | grep Modify | cut -f1 --complement -d " " | sed 's/^[ \t]*//;s/[ \t]*$//')"
  cert_file_renewal_epoch="$(date --date="$cert_file_renewal_date" +"%s")"
  ## Set full filename path using know directory structure and zonefile naming convention
  filename="/mnt/docker/nsd/zones/db.$domainname"
  ## Get dane hash from zonefile
  danezone=$(exec cat $filename | grep "_443._tcp.$domainname" | cut -d " " -f7 | xargs)
  ## Calculate dane SHA256 hash based on the Letsencrypt certificate
  openssloutput=$(openssl x509 -in /etc/letsencrypt/live/$domainname/cert.pem -outform DER | openssl sha256)
  ## Get DANE hash from openssl output
  danecert=$(exec echo $openssloutput | cut -f2 -d "=" | xargs)
  
  ## Now, let's check if certbot renewal (which is run every 12 hours on my Debian server) has resulted in a new certficate in the past hour
  if (( $current_epoch - $cert_file_renewal_epoch < 21000  )); then
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
                  sed -i "/_443._tcp.$domainname. IN TLSA 1/c\_443._tcp.$domainname. IN TLSA 1 0 1 $danezone ; old-dane-hash\n_443._tcp.$domainname. IN TLSA 1 0 1 $danecert" $filename

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