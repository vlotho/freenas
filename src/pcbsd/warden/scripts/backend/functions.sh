#!/bin/sh
# Functions / variables for warden
######################################################################
# DO NOT EDIT 

# Source local functions
. /usr/local/share/pcbsd/scripts/functions.sh

# Installation directory
PROGDIR="/usr/local/share/warden"

# Jail location
JDIR="$(grep ^JDIR: /usr/local/etc/warden.conf | cut -d' ' -f2)"
export JDIR

# Set arch type
REALARCH=`uname -m`
export REALARCH
if [ -z "$ARCH" ] ; then
  ARCH="$REALARCH"
  export ARCH
fi

# Location of pcbsd.conf file
PCBSD_ETCCONF="/usr/local/etc/pcbsd.conf"

# Network interface to use
NIC="$(grep ^NIC: /usr/local/etc/warden.conf | cut -d' ' -f2)"
export NIC

# Tmp directory
WTMP="$(grep ^WTMP: /usr/local/etc/warden.conf | cut -d' ' -f2)"
export WTMP

# Temp file for dialog responses
ATMP="/tmp/.wans"
export ATMP

# Warden Version
WARDENVER="1.2"
export WARDENVER

# Dirs to nullfs mount in X jail
NULLFS_MOUNTS="/tmp /media /usr/home"

# Clone directory
CDIR="${JDIR}/clones"

downloadpluginjail() {
  local _ver="${1}"

  SYSVER=`echo "${_ver}" | sed -E 's|^FreeNAS-(([0-9]+\.){2}[0-9]+).*|\1|'`
  SYSREL=`echo "${_ver}" | sed -E 's|^FreeNAS-([0-9]+\.){2}[0-9]+-([a-zA-Z0-9]+)-.*|\2|'`
  SYSARCH=`echo "${_ver}" | sed -E 's#^(.*)(x86|x64)#\2#'`

  SF="http://downloads.sourceforge.net/project/freenas"
  URL="${SF}/FreeNAS-${SYSVER}/${SYSREL}/${SYSARCH}/plugins"

  PJAIL="FreeNAS-${SYSVER}-${SYSREL}-${SYSARCH}.Plugins_Jail.pbi"
  PJAILSHA256="${PJAIL}.sha256"

  if [ ! -d "${JDIR}" ] ; then mkdir -p "${JDIR}" ; fi
  cd ${JDIR}

  echo "Fetching jail environment. This may take a while..."

  if [ ! -e "${PJAIL}" ] ; then
     echo "Downloading ${URL}/${PJAIL} ..."
     get_file "${URL}/${PJAIL}" "${PJAIL}" 3
     [ $? -ne 0 ] && printerror "Error while downloading the pluginjail."
  fi

  if [ ! -e "${PJAILSHA256}" ] ; then
     echo "Downloading ${URL}/${PJAILSHA256} ..."
     get_file "${URL}/${PJAILSHA256}" "${PJAILSHA256}" 3
     [ $? -ne 0 ] && printerror "Error while downloading the pluginjail sha256."
  fi

  [ "$(sha256 -q ${PJAIL})" != "$(cat ${PJAILSHA256})" ] &&
    printerror "Error in download data, checksum mismatch. Please try again later."

  # Creating ZFS dataset?
  isDirZFS "${JDIR}"
  if [ $? -eq 0 ] ; then
    local zfsp=`getZFSRelativePath "${WORLDCHROOT}"`

    # Use ZFS base for cloning
    echo "Creating ZFS ${WORLDCHROOT} dataset..."
    tank=`getZFSTank "${JDIR}"`
    isDirZFS "${WORLDCHROOT}" "1"
    if [ $? -ne 0 ] ; then
       zfs create -o mountpoint=/${tank}${zfsp} -p ${tank}${zfsp}
       if [ $? -ne 0 ] ; then exit_err "Failed creating ZFS base dataset"; fi
       mkdir -p "${WORLDCHROOT}/.plugins" >/dev/null 2>&1
    fi

    pbi_add -e --no-checksig -p ${WORLDCHROOT} ${PJAIL}
    if [ $? -ne 0 ] ; then exit_err "Failed extracting ZFS chroot environment"; fi

    zfs snapshot ${tank}${zfsp}@clean
    if [ $? -ne 0 ] ; then exit_err "Failed creating clean ZFS base snapshot"; fi
    rm ${PJAIL}
  else
    # Save the chroot tarball
    mv ${PJAIL} ${WORLDCHROOT}
  fi
  rm ${PJAILSHA256}
};

### Download the chroot
downloadchroot() {
  # XXX If this is PCBSD, pbreg get /PC-BSD/Version
  SYSVER=`uname -r | cut -f1 -d'-'`
  FBSD_TARBALL="fbsd-release.tbz"
  FBSD_TARBALL_CKSUM="${FBSD_TARBALL}.md5"

  # Set the mirror URL, may be overridden by setting MIRRORURL environment variable
  if [ -z "${MIRRORURL}" ]; then
    get_mirror
    MIRRORURL="$VAL"
  fi

  if [ ! -d "${JDIR}" ] ; then mkdir -p "${JDIR}" ; fi
  cd ${JDIR}

  echo "Fetching jail environment. This may take a while..."
  echo "Downloading ${MIRRORURL}/${SYSVER}/${ARCH}/netinstall/${FBSD_TARBALL} ..."

  if [ ! -e "$FBSD_TARBALL" ] ; then
     get_file "${MIRRORURL}/${SYSVER}/${ARCH}/netinstall/${FBSD_TARBALL}" "$FBSD_TARBALL" 3
     [ $? -ne 0 ] && printerror "Error while downloading the portsjail."
  fi

  if [ ! -e "$FBSD_TARBALL_CKSUM" ] ; then
     get_file "${MIRRORURL}/${SYSVER}/${ARCH}/netinstall/${FBSD_TARBALL_CKSUM}" "$FBSD_TARBALL_CKSUM" 3
     [ $? -ne 0 ] && printerror "Error while downloading the portsjail."
  fi

  [ "$(md5 -q ${FBSD_TARBALL})" != "$(cat ${FBSD_TARBALL_CKSUM})" ] &&
    printerror "Error in download data, checksum mismatch. Please try again later."

  # Creating ZFS dataset?
  isDirZFS "${JDIR}"
  if [ $? -eq 0 ] ; then
    local zfsp=`getZFSRelativePath "${WORLDCHROOT}"`

    # Use ZFS base for cloning
    echo "Creating ZFS ${WORLDCHROOT} dataset..."
    tank=`getZFSTank "${JDIR}"`
    isDirZFS "${WORLDCHROOT}" "1"
    if [ $? -ne 0 ] ; then
       zfs create -o mountpoint=/${tank}${zfsp} -p ${tank}${zfsp}
       if [ $? -ne 0 ] ; then exit_err "Failed creating ZFS base dataset"; fi
    fi

    tar xvpf ${FBSD_TARBALL} -C ${WORLDCHROOT} 2>/dev/null
    if [ $? -ne 0 ] ; then exit_err "Failed extracting ZFS chroot environment"; fi

    zfs snapshot ${tank}${zfsp}@clean
    if [ $? -ne 0 ] ; then exit_err "Failed creating clean ZFS base snapshot"; fi
    rm ${FBSD_TARBALL}
  else
    # Save the chroot tarball
    mv ${FBSD_TARBALL} ${WORLDCHROOT}
  fi
  rm ${FBSD_TARBALL_CKSUM}
};


### Mount all needed filesystems for the jail
mountjailxfs() {
  for nullfs_mount in ${NULLFS_MOUNTS}; do
    if [ ! -d "${JDIR}/${1}${nullfs_mount}" ] ; then
      mkdir -p "${JDIR}/${1}${nullfs_mount}"
    fi
    if is_symlinked_mountpoint ${nullfs_mount}; then
      echo "${nullfs_mount} has symlink as parent, not mounting"
      continue
    fi

    echo "Mounting ${JDIR}/${1}${nullfs_mount}"
    mount_nullfs ${nullfs_mount} ${JDIR}/${1}${nullfs_mount}
  done

  # Add support for linprocfs for ports that need linprocfs to build/run
  if [  ! -d "${JDIR}/${1}/compat/linux/proc" ]; then
    mkdir -p ${JDIR}/${1}/compat/linux/proc
  fi
  if is_symlinked_mountpoint ${JDIR}/${1}/compat/linux/proc; then
    echo "${JDIR}/${1}/compat/linux/proc has symlink as parent, not mounting"
    return
  fi
  echo "Enabling linprocfs support."
  mount -t linprocfs linprocfs ${JDIR}/${1}/compat/linux/proc
}

### Umount all the jail's filesystems
umountjailxfs() {
  status="0"
  # Umount all filesystems that are mounted into the portsjail
  for mountpoint in $(mount | grep ${JDIR}/${1}/ | cut -d" " -f3); do
    if [ "$mountpoint" = "${JDIR}/${1}/dev" ] ; then continue ; fi
    if [ "$mountpoint" = "${JDIR}/${1}/" ] ; then continue ; fi
    if [ "$mountpoint" = "${JDIR}/${1}" ] ; then continue ; fi
    echo "Unmounting $mountpoint"
    umount -f ${mountpoint}
    if [ $? -ne 0 ] ; then status="1" ; fi
  done
  # Now try to umount /dev
  umount -f ${JDIR}/${1}/dev 2>/dev/null >/dev/null
  return $status
}

# Check if PBI scripts are loaded in jail
checkpbiscripts() {
  if [ -z "${1}" ] ; then return ; fi
  if [ ! -e "${1}/usr/local/sbin/pbi_info" ] ; then
    copypbiscripts "${1}"
  elif [ "`ls -l /usr/local/sbin/pbi_info | awk '{print $5}'`" != "`ls -l ${1}/usr/local/sbin/pbi_info | awk '{print $5}'`" ] ; then 
    copypbiscripts "${1}"
  fi
}

# Copy PBI scripts to jail
copypbiscripts() {
  if [ -z "${1}" ] ; then return ; fi
  mkdir -p ${1}/usr/local/sbin >/dev/null 2>/dev/null
  cp /usr/local/sbin/pbi* ${1}/usr/local/sbin/
  chmod 755 ${1}/usr/local/sbin/pbi*

  # Copy rc.d pbid script
  mkdir -p ${1}/usr/local/etc/rc.d >/dev/null 2>/dev/null
  cp /usr/local/etc/rc.d/pbid ${1}/usr/local/etc/rc.d/

  # Copy any PBI manpages
  for man in `find /usr/local/man | grep pbi`
  do
    if [ ! -d "${1}`dirname $man`" ] ; then
      mkdir -p "${1}`dirname $man`"
    fi
    cp "${man}" "${1}${man}"
  done
}

mkportjail() {
  if [ -z "${1}" ] ; then return ; fi
  ETCFILES="resolv.conf passwd master.passwd spwd.db pwd.db group localtime"
  for file in ${ETCFILES}; do
    rm ${1}/etc/${file} >/dev/null 2>&1
    cp /etc/${file} ${1}/etc/${file}
  done
  
  # Need to symlink /home
  chroot ${1} ln -fs /usr/home /home

  # Make sure we remove our cleartmp rc.d script, causes issues
  [ -e "${1}/etc/rc.d/cleartmp" ] && rm ${1}/etc/rc.d/cleartmp
  # Flag this type
  touch ${JMETADIR}/jail-portjail
}

mkpluginjail() {
  if [ -z "${1}" ] ; then return ; fi
  ETCFILES="resolv.conf passwd master.passwd spwd.db pwd.db group localtime"
  for file in ${ETCFILES}; do
    rm ${1}/etc/${file} >/dev/null 2>&1
    cp /etc/${file} ${1}/etc/${file}
  done
  
  # Need to symlink /home
  chroot ${1} ln -fs /usr/home /home

  # Make sure we remove our cleartmp rc.d script, causes issues
  [ -e "${1}/etc/rc.d/cleartmp" ] && rm ${1}/etc/rc.d/cleartmp
  # Flag this type
  touch ${JMETADIR}/jail-pluginjail
}

mkZFSSnap() {
  isDirZFS "${1}" "1"
  if [ $? -ne 0 ] ; then printerror "Not a ZFS volume: ${1}" ; fi
  tank=`getZFSTank "$1"`
  rp=`getZFSRelativePath "$1"`
  zdate=`date +%Y-%m-%d-%H-%M-%S`
  zfs snapshot $tank${rp}@$zdate
}

listZFSSnap() {
  isDirZFS "${1}" "1"
  if [ $? -ne 0 ] ; then printerror "Not a ZFS volume: ${1}" ; fi
  tank=`getZFSTank "$1"`
  rp=`getZFSRelativePath "$1"`
  zfs list -t snapshot | grep -w "^${tank}${rp}" | cut -d '@' -f 2 | awk '{print $1}'
}

listZFSClone() {
  isDirZFS "${1}" "1"
  if [ $? -ne 0 ] ; then printerror "Not a ZFS volume: ${1}" ; fi
  tank=`getZFSTank "$1"`
  cdir=`getZFSRelativePath "${CDIR}"` 
  echo "Clone Directory: ${CDIR}"
  echo "-----------------------------------"
  zfs list | grep -w "^${tank}${cdir}/${2}" | awk '{print $5}' | sed "s|${CDIR}/${2}-||g"
}

rmZFSClone() {
  CLONEDIR="${CDIR}/${3}-${2}"
  isDirZFS "${CLONEDIR}" "1"
  if [ $? -ne 0 ] ; then printerror "Not a ZFS volume: ${CLONEDIR}" ; fi
  tank=`getZFSTank "${CLONEDIR}"`
  rp=`getZFSRelativePath "${CLONEDIR}"`
  zfs destroy ${tank}${rp}
}

rmZFSSnap() {
  isDirZFS "${1}" "1"
  if [ $? -ne 0 ] ; then printerror "Not a ZFS volume: ${1}" ; fi
  tank=`getZFSTank "$1"`
  rp=`getZFSRelativePath "$1"`
  zfs destroy $tank${rp}@$2
}

revertZFSSnap() {
  isDirZFS "${1}" "1"
  if [ $? -ne 0 ] ; then printerror "Not a ZFS volume: ${1}" ; fi
  tank=`getZFSTank "$1"`
  rp=`getZFSRelativePath "$1"`

  # Make sure this is a valid snapshot
  zfs list -t snapshot | grep -w "^${tank}${rp}" | cut -d '@' -f 2 | awk '{print $1}' | grep -q ${2}
  if [ $? -ne 0 ] ; then printerror "Invalid ZFS snapshot!" ; fi

  # Check if the jail is running first
  ${PROGDIR}/scripts/backend/checkstatus.sh "${3}"
  if [ "$?" = "0" ]; then
    restartJail="YES"
    # Make sure the jail is stopped
    ${PROGDIR}/scripts/backend/stopjail.sh "${3}"
    ${PROGDIR}/scripts/backend/checkstatus.sh "${3}"
    if [ "$?" = "0" ]; then
      printerror "Could not stop jail... Halting..."
    fi
  fi

  # Rollback the snapshot
  zfs rollback -R -f ${tank}${rp}@$2

  # If it was started, restart the jail now
  if [ "$restartJail" = "YES" ]; then
    ${PROGDIR}/scripts/backend/startjail.sh "${3}"
  fi
  
}

cloneZFSSnap() {
  isDirZFS "${1}" "1"
  if [ $? -ne 0 ] ; then printerror "Not a ZFS volume: ${1}" ; fi
  tank=`getZFSTank "$1"`
  rp=`getZFSRelativePath "$1"`
  cdir=`getZFSRelativePath "${CDIR}"`

  # Make sure this is a valid snapshot
  zfs list -t snapshot | grep -w "^${tank}${rp}" | cut -d '@' -f 2 | awk '{print $1}' | grep -q ${2}
  if [ $? -ne 0 ] ; then printerror "Invalid ZFS snapshot!" ; fi

  if [ -d "${CDIR}/${3}-${2}" ] ; then
     printerror "This snapshot is already cloned and mounted at: ${CDIR}/${3}-${2}"
  fi

  # Clone the snapshot
  zfs clone -p ${tank}${rp}@$2 ${tank}${cdir}/${3}-${2}

  echo "Snapshot cloned and mounted to: ${CDIR}/${3}-${2}"
}

set_warden_metadir()
{
   JMETADIR="${JDIR}/.${JAILNAME}.meta"
   export JMETADIR
}

get_ip_and_netmask()
{
   JIP=`echo "${1}" | cut -f1 -d'/'`
   JMASK=`echo "${1}" | cut -f2 -d'/' -s`
}

get_interface_addresses()
{
   ifconfig ${1} | grep -w inet | awk '{ print $2 }'
}

get_interface_ipv4_addresses()
{
   ifconfig ${1} | grep -w inet | awk '{ print $2 }'
}

get_interface_ipv6_addresses()
{
   ifconfig ${1} | grep -w inet6 | awk '{ print $2 }'
}

get_interface_address()
{
   ifconfig ${1} | grep -w inet | head -1 | awk '{ print $2 }'
}

get_interface_ipv4_address()
{
   ifconfig ${1} | grep -w inet | head -1 | awk '{ print $2 }'
}

get_interface_ipv6_address()
{
   ifconfig ${1} | grep -w inet6 | head -1 | awk '{ print $2 }'
}

get_interface_aliases()
{
   local _count

   _count=`ifconfig ${1} | grep -w inet | wc -l`
   _count="$(echo "${_count} - 1" | bc)"

   ifconfig ${1} | grep -w inet | tail -${_count} | awk '{ print $2 }'
}

get_interface_ipv4_aliases()
{
   local _count

   _count=`ifconfig ${1} | grep -w inet | wc -l`
   _count="$(echo "${_count} - 1" | bc)"

   ifconfig ${1} | grep -w inet | tail -${_count} | awk '{ print $2 }'
}

get_interface_ipv6_aliases()
{
   local _count

   _count=`ifconfig ${1} | grep -w inet | wc -l`
   _count="$(echo "${_count} - 1" | bc)"

   ifconfig ${1} | grep -w inet6 | tail -${_count} | awk '{ print $2 }'
}

get_default_route()
{
   netstat -f inet -nr | grep '^default' | awk '{ print $2 }'
}

get_default_interface()
{
   netstat -f inet -nrW | grep '^default' | awk '{ print $7 }'
}

get_bridge_interfaces()
{
   ifconfig -a | grep -E '^bridge[0-9]+' | cut -f1 -d:
}

get_bridge_members()
{
   ifconfig ${1} | grep -w member | awk '{ print $2 }'
}

get_bridge_interface_by_ipv4_network()
{
   local network="${1}"
   local bridges="$(get_bridge_interfaces)"

   if [ -z "${network}" ]
   then
      return 1
   fi

   for _bridge in ${bridges}
   do
      local ips="$(get_interface_ipv4_aliases "${_bridge}")"
      for _ip in ${ips}
      do
         if in_ipv4_network "${_ip}" "${network}"
         then
            echo "${_bridge}"
            return 0
         fi
      done
   done

   return 1
}

get_bridge_interface_by_ipv6_network()
{
   local network="${1}"
   local bridges="$(get_bridge_interfaces)"

   if [ -z "${network}" ]
   then
      return 1
   fi

   for _bridge in ${bridges}
   do
      local ips="$(get_interface_ipv6_aliases "${_bridge}")"
      for _ip in ${ips}
      do
         if in_ipv6_network "${_ip}" "${network}"
         then
            echo "${_bridge}"
            return 0
         fi
      done
   done

   return 1
}

is_bridge_member()
{
   local _bridge="${1}"
   local _iface="${2}"

   for _member in `get_bridge_members ${_bridge}`
   do
      if [ "${_member}" = "${_iface}" ] ; then
         return 0
      fi
   done

   return 1
}

jail_interfaces_down()
{
   local _jid="${1}"
   local _bridgeif
   local _epaira
   local _epairb

   _epairb=`jexec ${_jid} ifconfig -a | grep '^epair' | cut -f1 -d:`
   if [ -n "${_epairb}" ] ; then
      _epaira=`echo ${_epairb} | sed -E 's|b$|a|'`
      _bridgeif=

      for _bridge in `ifconfig -a | grep -E '^bridge[0-9]+' | cut -f1 -d:`
      do
         for _member in `ifconfig ${_bridge} | grep member | awk '{ print $2 }'`
         do
            if [ "${_member}" = "${_epaira}" ] ; then
               _bridgeif="${_bridge}"
                break
            fi
         done
         if [ -n "${_bridgeif}" ] ; then
            break
         fi
      done

      jexec ${_jid} ifconfig ${_epairb} down
      ifconfig ${_epaira} down
      ifconfig ${_epaira} destroy
      _count=`ifconfig ${_bridgeif} | grep member | awk '{ print $2 }' | wc -l`
      if [ "${_count}" -le "1" ] ; then
         ifconfig ${_bridgeif} destroy
      fi
   fi
}

enable_cron()
{
   cronscript="${PROGDIR}/scripts/backend/cronsnap.sh"
   grep -q "${cronscript}" /etc/crontab
   if [ $? -eq 0 ] ; then return 0 ; fi
   echo "2     *        *       *       *        root    ${cronscript}" >> /etc/crontab
   # Restart cron
   /etc/rc.d/cron restart >/dev/null 2>/dev/null
}

fix_old_meta()
{
   for i in `ls -d ${JDIR}/.*.meta 2>/dev/null`
   do
      if [ -e "${i}/xjail" ] ; then
         touch ${i}/jail-portjail 2>/dev/null
      fi
      if [ -e "${i}/linuxjail" ] ; then
         touch ${i}/jail-linux 2>/dev/null
      fi
   done
}

is_ipv4()
{
   local addr="${1}"
   local res=1

   local ipv4="$(/usr/local/bin/sipcalc "${addr}"|head -1|cut -f2 -d'['|awk '{ print $1 }')"
   if [ "${ipv4}" = "ipv4" ]
   then
      res=0
   fi

   return ${res}
}

is_ipv6()
{
   local addr="${1}"
   local res=1

   local ipv6="$(/usr/local/bin/sipcalc "${addr}"|head -1|cut -f2 -d'['|awk '{ print $1 }')"
   if [ "${ipv6}" = "ipv6" ]
   then
      res=0
   fi

   return ${res}
}

in_ipv4_network()
{
   local addr="${1}"
   local network="${2}"
   local res=1

   local start="$(/usr/local/bin/sipcalc "${network}"|awk '/^Usable/ { print $4 }')"
   local end="$(/usr/local/bin/sipcalc "${network}"|awk '/^Usable/ { print $6 }')"

   local iaddr="$(/usr/local/bin/sipcalc "${addr}"|awk '/(decimal)/ { print $5 }')"
   local istart="$(/usr/local/bin/sipcalc "${start}"|awk '/(decimal)/ { print $5 }')"
   local iend="$(/usr/local/bin/sipcalc "${end}"|awk '/(decimal)/ { print $5 }')"

   if [ "${iaddr}" -ge "${istart}" -a "${iaddr}" -le "${iend}" ]
   then
      res=0
   fi

   return ${res}
}

ipv6_to_binary()
{
   echo ${1}|awk '{
      split($1, octets, ":");
      olen = length(octets);
		
      bnum = "";
      for (i = 1;i <= olen;i++) {
         tbnum = "";
         dnum = int(sprintf("0x%s", octets[i]));
         for (;;) {
            rem = int(dnum % 2);
            if (rem == 0) 
               tbnum = sprintf("0%s", tbnum);
            else		
               tbnum = sprintf("1%s", tbnum);
            dnum /= 2;
            if (dnum < 1)
               break;
         }
         bnum = sprintf("%s%016s", bnum, tbnum);
      }
      printf("%s", bnum);
   }'
}

in_ipv6_network()
{
   local addr="${1}"
   local network="${2}"
   local mask="$(echo "${network}"|cut -f2 -d'/' -s)"
   local res=1

   local addr="$(/usr/local/bin/sipcalc "${addr}"|awk \
      '/^Expanded/ { print $4}')"
   local start="$(/usr/local/bin/sipcalc "${network}"|egrep \
      '^Network range'|awk '{ print $4 }')"

   local baddr="$(ipv6_to_binary "${addr}")"
   local bstart="$(ipv6_to_binary "${start}")"

   local baddrnet="$(echo "${baddr}"|awk -v mask="${mask}" \
      '{ s = substr($0, 1, mask); printf("%s", s); }')"
   local bstartnet="$(echo "${bstart}"|awk -v mask="${mask}" \
      '{ s = substr($0, 1, mask); printf("%s", s); }')"

   if [ "${baddrnet}" = "${bstartnet}" ]
   then
      res=0
   fi

   return ${res}
}

bootstrap_pkgng()
{
  cd ${1} 
  SYSVER="$(uname -r)"
  echo "Boot-strapping pkgng"
  mkdir -p ${1}/usr/local/etc
  cp /usr/local/etc/pkg-pubkey.cert ${1}/usr/local/etc/

  echo '#!/bin/sh
  tar xvf pkg.txz --exclude +MANIFEST --exclude +MTREE_DIRS 2>/dev/null
  pkg add pkg.txz
  rm pkg.txz
  ARCH=$(uname -m)
  REL=$(uname -r)
  echo "packagesite: http://getmirror.pcbsd.org/packages/$REL/$ARCH" >/usr/local/etc/pkg.conf
  echo "HTTP_MIRROR: http" >>/usr/local/etc/pkg.conf
  echo "PUBKEY: /usr/local/etc/pkg-pubkey.cert" >>/usr/local/etc/pkg.conf
  echo "PKG_CACHEDIR: /usr/local/tmp" >>/usr/local/etc/pkg.conf
  pkg install -y pcbsd-utils
  exit $?
' > ${1}/bootstrap-pkgng
  chmod 755 ${1}/bootstrap-pkgng

  if [ -e "pkg.txz" ] ; then rm pkg.txz ; fi
  get_file_from_mirrors "/packages/${SYSVER}/${ARCH}/Latest/pkg.txz" "pkg.txz"
  if [ $? -eq 0 ] ; then
    chroot ${1} /bootstrap-pkgng
    if [ $? -eq 0 ] ; then
      rm ${1}/bootstrap-pkgng
      chroot ${1} pc-extractoverlay server --sysinit
      return 0
    fi
  fi
  echo "Failed boot-strapping PKGNG, most likely cause is internet connection failure."
  rm ${1}/bootstrap-pkgng
  return 1
}

ipv4_configured()
{
   local iface="${1}"
   local jid="${2}"
   local jexec=

   if [ -n "${jid}" ] ; then
      jexec="jexec ${jid}"
   fi

   ${jexec} ifconfig "${iface}" | grep -qw inet 2>/dev/null
}

ipv6_configured()
{
   local iface="${1}"
   local jid="${2}"
   local jexec=

   if [ -n "${jid}" ] ; then
      jexec="jexec ${jid}"
   fi

   ${jexec} ifconfig "${iface}" | grep -qw inet6 2>/dev/null
}
