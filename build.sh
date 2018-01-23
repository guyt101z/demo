#!/bin/bash

# This file wraps the bootstrap processes for the SITCH service.

warn=$(tput bold)$(tput setaf 1)
info=$(tput bold)$(tput setaf 2)
norm=$(tput sgr0)

# Set env vars
source .env

# First, we need to make sure all of our required env vars are set...
set BAIL_NO_ENV="NO"
if [ "${SERVER_NAME}" == "unset" ]; then
  echo "${warn}Missing DNS_NAME in .env file!${norm}"
  set BAIL_NO_ENV="YES"
fi
if [ "${CERTBOT_EMAIL}" == "unset" ]; then
  echo "${warn}Missing EMAIL in .env file!${norm}"
  set BAIL_NO_ENV="YES"
fi
if [ "${SLACK_WEBHOOK}" == "unset" ]; then
  echo "${warn}Missing SLACK_WEB_HOOK in .env file!${norm}"
  set BAIL_NO_ENV="YES"
fi
if [ "${BAIL_NO_ENV}" == "YES" ]; then
  echo "${warn}Exiting because of missing env vars!  Check .env file!${norm}"
  exit 1
fi


# Next we try to determine the distribution...
if [ -f /etc/lsb-release ]; then
  export `cat /etc/lsb-release | grep DISTRIB_ID | head -1`
elif [ -f /etc/redhat-release ]; then
  export DISTRIB_ID=`cat /etc/redhat-release | head -1 | awk '{print $1}'`
fi

# If we can't determine the distribution, we exit.
if [ -z ${DISTRIB_ID} ]; then
  echo "${warn}Unable to determine distribution! Exiting!!${norm}"
  exit 1
fi

# We look to see if the distribution is supported.  If not, we exit.
case "${DISTRIB_ID}" in
    Ubuntu)
        echo "${info}Ubuntu found!${norm}"
        /bin/bash ./ubuntu/install-docker.sh
        ;;
    Debian)
        echo "${info}Debian found!${norm}"
        /bin/bash ./debian/install-docker.sh
        ;;
    *)
        echo "${warn}Unsupported OS: ${DISTRIB_ID}! EXITING${norm}"
        exit 1
esac

# Install docker-compose...
/bin/bash ./general/install-docker-compose.sh
# Get letsencrypt certs...
/bin/bash ./general/lets-encrypt.sh

# We bring up the stack, knowing that Logstash will be in a restart loop until
# seeded certs are present in Vault.
/usr/local/bin/docker-compose up -d
echo "${info}Sleep for 30s, give Vault time to go live.${norm}"
sleep 30
docker ps -a
docker logs sitch_vault
echo "${info}---LISTENING SERVICES---${norm}"
netstat -putan | grep LISTEN
echo "${info}-------${norm}"
# Requires copying Vault keys and root token, then pasting 3 keys back
echo "${info}Seeding Vault:${norm}"
/bin/bash ./general/vault.sh

sleep 5
echo "${info}------${norm}"
# Vault root token will needed for this script and for docker-compose
# echo Paste the root token generated by Vault
# read VAULT_TOKEN
# export VAULT_TOKEN
echo "${info}Seeding Logstash:${norm}"
/bin/bash ./general/logstash.sh
echo "${info}------${norm}"
echo "${info}Setting Vault token prior to fonal convergence of docker-compose:${norm}"
export VAULT_TOKEN=`cat ./vault_root_token | head -1 | tail -1`
echo "${info}Vault token: ${VAULT_TOKEN} ${norm}"
if [ "${VAULT_TOKEN}" == "" ]; then
  echo "${warn}Unable to get vault token! \nTearing down environment, check your config and start again.${norm}"
  docker-compose down
  exit 1
fi
echo "${info}------${norm}"

# Now we docker-compose up with new env var for vault access.
docker-compose up -d

sleep 10

docker ps
echo "${info}Build script is complete.  Please confirm that service is live by visiting the Kibana dashboard.${norm}"
