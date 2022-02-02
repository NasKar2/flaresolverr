#!/bin/sh
# Build an iocage jail under TrueNAS 12.3 with  Flaresolverr
# https://github.com/NasKar2/sepapps-freenas-iocage

# Check for root privileges
if ! [ $(id -u) = 0 ]; then
   echo "This script must be run with root privileges"
   exit 1
fi

# Initialize defaults
JAIL_IP=""
JAIL_NAME=""
DEFAULT_GW_IP=""
INTERFACE=""
VNET=""
POOL_PATH=""
APPS_PATH=""
FLARESOLVERR_DATA=""
MEDIA_LOCATION=""
TORRENTS_LOCATION=""
USE_BASEJAIL="-b"

SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "$SCRIPT")
. $SCRIPTPATH/flaresolverr-config
CONFIGS_PATH=$SCRIPTPATH/configs
RELEASE=$(freebsd-version | cut -d - -f -1)"-RELEASE"

# Check for flaresolverr-config and set configuration
if ! [ -e $SCRIPTPATH/flaresolverr-config ]; then
  echo "$SCRIPTPATH/flaresolverr-config must exist."
  exit 1
fi

# Check that necessary variables were set by flaresolverr-config
if [ -z $JAIL_IP ]; then
  echo 'Configuration error: JAIL_IP must be set'
  exit 1
fi
if [ -z $DEFAULT_GW_IP ]; then
  echo 'Configuration error: DEFAULT_GW_IP must be set'
  exit 1
fi
if [ -z $INTERFACE ]; then
  INTERFACE="vnet0"
  echo "INTERFACE defaulting to 'vnet0'"
fi
if [ -z $VNET ]; then
  VNET="on"
  echo "VNET defaulting to 'on'"
fi
if [ -z $POOL_PATH ]; then
  POOL_PATH="/mnt/$(iocage get -p)"
  echo "POOL_PATH defaulting to "$POOL_PATH
fi
if [ -z $APPS_PATH ]; then
  APPS_PATH="apps"
  echo "APPS_PATH defaulting to 'apps'"
fi
if [ -z $JAIL_NAME ]; then
  JAIL_NAME="flaresolverr"
  echo "JAIL_NAME defaulting to 'flaresolverr'"
fi

if [ -z $FLARESOLVERR_DATA ]; then
  FLARESOLVERR_DATA="flaresolverr"
  echo "FLARESOLVERR_DATA defaulting to 'flaresolverr'"
fi

if [ -z $MEDIA_LOCATION ]; then
  MEDIA_LOCATION="media"
  echo "MEDIA_LOCATION defaulting to 'media'"
fi

if [ -z $TORRENTS_LOCATION ]; then
  TORRENTS_LOCATION="torrents"
  echo "TORRENTS_LOCATION defaulting to 'torrents'"
fi

#
# Create Jail
RELEASE="12.3-RELEASE"
if ! iocage create --name "${JAIL_NAME}" -r "${RELEASE}" ip4_addr="${INTERFACE}|${JAIL_IP}/24" defaultrouter="${DEFAULT_GW_IP}" boot="on" host_hostname="${JAIL_NAME}" vnet="${VNET}" ${USE_BASEJAIL}
then
	echo "Failed to create jail"
	exit 1
fi
# rm /tmp/pkg.json

#
# update

# Make pkg upgrade get the latest repo
iocage exec ${JAIL_NAME} "mkdir -p /mnt/configs"
iocage fstab -a ${JAIL_NAME} ${CONFIGS_PATH} /mnt/configs nullfs rw 0 0
iocage exec ${JAIL_NAME} "mkdir -p /usr/local/etc/pkg/repos/"
iocage exec ${JAIL_NAME} cp -f /mnt/configs/FreeBSD.conf /usr/local/etc/pkg/repos/FreeBSD.conf
exit
#
# Upgrade to the lastest repo
iocage exec ${JAIL_NAME} pkg update -y
iocage exec ${JAIL_NAME} pkg upgrade

#
# Install pkgs
iocage exec ${JAIL_NAME} pkg install -y nano git-tiny

#
# Install with GIT
iocage exec ${JAIL_NAME} cd /usr/local/share
iocage exec ${JAIL_NAME} git clone https://github.com/FlareSolverr/FlareSolverr.git
echo "git installed"
iocage exec ${JAIL_NAME} pkg install -y npm-node14 chromium
exit
iocage exec ${JAIL_NAME} cd /usr/local/share/FlareSolverr
iocage exec ${JAIL_NAME} setenv PUPPETEER_SKIP_CHROMIUM_DOWNLOAD true
iocage exec ${JAIL_NAME} setenv PUPPETEER_EXECUTABLE_PATH /usr/local/bin/chrome
iocage exec ${JAIL_NAME} npm install
iocage exec ${JAIL_NAME} node node_modules/puppeteer/install.js
iocage exec ${JAIL_NAME} npm install puppeteer@1.2.0
iocage exec ${JAIL_NAME} npm install puppeteer
iocage exec ${JAIL_NAME} npm run build
iocage exec ${JAIL_NAME} npm start



#
# mount configs to jail for rc.d file 
iocage fstab -a ${JAIL_NAME} ${CONFIGS_PATH} /mnt/configs nullfs rw 0 0
#iocage fstab -a ${JAIL_NAME} ${flaresolverr_config} /config nullfs rw 0 0
#iocage fstab -a ${JAIL_NAME} ${POOL_PATH}/${MEDIA_LOCATION}/books /mnt/library nullfs rw 0 0
#iocage fstab -a ${JAIL_NAME} ${POOL_PATH}/${TORRENTS_LOCATION} /mnt/torrents nullfs rw 0 0
iocage exec ${JAIL_NAME} cp -f /mnt/configs/flaresolverr /usr/local/etc/rc.d/flaresolverr
iocage exec ${JAIL_NAME} chmod u+x /usr/local/etc/rc.d/flaresolverr
iocage exec ${JAIL_NAME} sysrc flaresolverr_enable="YES"
exit
#iocage restart ${JAIL_NAME}

# add media user
iocage exec ${JAIL_NAME} "pw user add media -c media -u 8675309  -d /config -s /usr/bin/nologin"
  
# add media group to media user
#iocage exec ${JAIL_NAME} pw groupadd -n media -g 8675309
#iocage exec ${JAIL_NAME} pw groupmod media -m media
#iocage restart ${JAIL_NAME} 

#
# Install Flaresolverr
iocage exec ${JAIL_NAME} "fetch https://github.com/Thefrank/freebsd-port-sooners/releases/download/20210613/radarrv3-3.2.2.5080.txz"
iocage exec ${JAIL_NAME} "pkg install -y radarrv3-3.2.2.5080.txz"
iocage exec ${JAIL_NAME} "fetch "https://readarr.servarr.com/v1/update/healthchecks/updatefile?os=bsd&arch=x64&runtime=netcore" -o /readarr.tar.gz"
iocage exec ${JAIL_NAME} "mkdir /usr/local/share/flaresolverr"
iocage exec ${JAIL_NAME} "tar -xf /flaresolverr.tar.gz -C /usr/local/share/flaresolverr"
iocage exec ${JAIL_NAME} "rm /usr/local/etc/rc.d/radarr"

iocage exec ${JAIL_NAME} chown -R media:media /usr/local/share/flaresolverr /config
iocage exec ${JAIL_NAME} -- mkdir /usr/local/etc/rc.d
iocage exec ${JAIL_NAME} cp -f /mnt/configs/flaresolverr /usr/local/etc/rc.d/radarr
iocage exec ${JAIL_NAME} chmod u+x /usr/local/etc/rc.d/flaresolverr
#iocage exec ${JAIL_NAME} sed -i '' "s/radarrdata/${RADARR_DATA}/" /usr/local/etc/rc.d/radarr
iocage exec ${JAIL_NAME} sysrc flaresolverr_enable="YES"
iocage exec ${JAIL_NAME} sysrc flaresolverr_user="media"
iocage exec ${JAIL_NAME} sysrc flaresolverr_group="media"
iocage exec ${JAIL_NAME} sysrc flaresolverr_data_dir="/config"
iocage exec ${JAIL_NAME} service flaresolverr start
echo "Radarr installed"

#
# Make pkg upgrade get the latest repo
#iocage exec ${JAIL_NAME} mkdir -p /usr/local/etc/pkg/repos/
#iocage exec ${JAIL_NAME} cp -f /mnt/configs/FreeBSD.conf /usr/local/etc/pkg/repos/FreeBSD.conf

#
# Upgrade to the lastest repo
#iocage exec ${JAIL_NAME} pkg upgrade -y
#iocage restart ${JAIL_NAME}


#
# remove /mnt/configs as no longer needed
#iocage fstab -r ${JAIL_NAME} ${CONFIGS_PATH} /mnt/configs nullfs rw 0 0

# Make media owner of data directories
#chown -R media:media ${POOL_PATH}/${MEDIA_LOCATION}
#chown -R media:media ${POOL_PATH}/${TORRENTS_LOCATION}

echo
echo "Flaresolverr should be available at http://${JAIL_IP}:8787"
