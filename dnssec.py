# Auteur laster13 de mondedie.fr

import xmlrpc.client
import sys
import os
import subprocess
import fileinput
import requests
import json

api = xmlrpc.client.ServerProxy('https://rpc.gandi.net/xmlrpc/')

apikey = 'xxxxxxxxxxxxxxxxxxxx' ## cle de production gandi "https://v4.gandi.net/admin/api_key"
webhook_url = 'https://hooks.slack.com/services/xxxxxxx/xxxxxxx/xxxxxxxxxxxx' ## mettre votre webhook_url

# variable pour le nom de domaine
cmd = "grep name /mnt/docker/nsd/conf/nsd.conf | cut -d ':' -f2 | tr '\n' ' '"
process = subprocess.Popen(cmd, stdout=subprocess.PIPE, shell=True)
temp = process.communicate()[0]
domain = str(temp.decode())[1:-1]

# Affiche le fingerprint actuel de gandi
keys = api.domain.dnssec.list(apikey, domain)
fichier = open("liste.txt", "w")  
fichier.write(str(keys))
fichier.close()

# Affiche l'ID du fingerprint
cmd = "grep id liste.txt | cut --delimiter=, -f7 | cut -d ',' -f1 | cut -d ':' -f2 | cut -d ' ' -f2 | tr '\n' ' '"
process = subprocess.Popen(cmd, stdout=subprocess.PIPE, shell=True)
id = process.communicate()[0]
a = str(id.decode())[0:-1]
a = int(a)

# Suppression du fingerprint
op = api.domain.dnssec.delete(apikey, a)
os.remove('liste.txt')

# nouvelles cles
os.system('docker exec nsd keygen '+ domain)

# serial actuel de la zone
for line in open("/mnt/docker/nsd/zones/db."+ domain):
 if "Serial" in line:
  cmd = "grep Serial /mnt/docker/nsd/zones/db."+ domain
  process = subprocess.Popen(cmd, stdout=subprocess.PIPE, shell=True)
  serial = process.communicate()[0]
  serial = str(serial.decode())[1:-10]
  serial = serial.strip ()
  serial = int(serial)

# nouveau serial
cmd = "date -d '+1 day' +'%Y%m%d%H' | tr '\n' ' '"
process = subprocess.Popen(cmd, stdout=subprocess.PIPE, shell=True)
newserial = process.communicate()[0]
newserial = int(newserial)

# modif serial dans la zone
for line in fileinput.input("/mnt/docker/nsd/zones/db."+ domain, inplace=True):
 print(line.replace(str(serial), str(newserial)), end='')

# date expiration pour la signature dnssec
cmd = "date -d '+6 months' +'%Y%m%d%H%M%S' | tr '\n' ' '"
process = subprocess.Popen(cmd, stdout=subprocess.PIPE, shell=True)
date_expire = process.communicate()[0]
date_expire = int(date_expire)
date_expire = str(date_expire)

# signature de la zone DNS
os.system('docker exec nsd nsd-checkzone '+ domain + ' /zones/db.'+ domain + ' >> zone.log')
for line in open("zone.log"):
 if "ok" in line:
  cmd = "grep ok zone.log"
  process = subprocess.Popen(cmd, stdout=subprocess.PIPE, shell=True)
  result = process.communicate()[0]
  final = str(result.decode())[0:-1]
  if final == 'zone' + ' ' +domain +' ''is ok':
   os.system('docker exec nsd signzone '+domain+' '+date_expire)
   os.remove('zone.log')
  else:
   slack_data = {'text': 'Une erreur est survenue pendant la mise a jour de la zone DNS. Merci de verifier la conformite avec la commande suivante :docker exec nsd nsd-checkzone '+ domain + ' /zones/db.'+ domain}
   response = requests.post(
      webhook_url, data=json.dumps(slack_data),
      headers={'Content-Type': 'application/json'}
      )
   os.remove('zone.log')

# recuperer le nouveau fingerprint       
os.system('docker exec nsd ds-records '+ domain + ' >> dnskey.log') 
for line in open("dnskey.log"):
 if "DNSKEY" in line:
   cmd = "grep DNSKEY dnskey.log | cut -d ' ' -f4 | tr '\n' ' '"
   process = subprocess.Popen(cmd, stdout=subprocess.PIPE, shell=True)
   fingerprint = process.communicate()[0]
   condensat = str(fingerprint.decode())[0:-1]

# Envoi du fingerprint chez gandi
op = api.domain.dnssec.create(apikey, domain, {
"flags": 257,
"algorithm": 14,
"public_key": condensat})
slack_data = {'text': 'Le nouveau fingerprint est bien enregistre chez Gandi :' + '\n\n' +condensat + '\n\n' + 'La zone DNS a ete mise a jour et signee avec DNSSEC. Merci de verifier la conformite 10 minutes apres la notification avec : http://dnsviz.net/d/'+domain +'/analyze/ et https://dnssec-debugger.verisignlabs.com/'+domain}
response = requests.post(
     webhook_url, data=json.dumps(slack_data),
     headers={'Content-Type': 'application/json'}
      )
os.remove('dnskey.log')
