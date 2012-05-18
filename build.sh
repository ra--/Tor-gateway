#!/bin/bash

# Purpose: Build Tor gateway image and create VirtualBox VM
# by ra (2012)

VERSION="0.5.2"
NAME="Tor gateway ${VERSION}"
BUILD_THREADS='3'

FILENAME='OpenWrt-ImageBuilder-x86-for-Linux-i686.tar.bz2'
FILEURL='http://backfire.openwrt.org/10.03.1/x86_generic/'
FILEDIR='OpenWrt-ImageBuilder-x86-for-Linux-i686'
MD5SUM='c4f75b9f2350db7cfae0d5299688b8ff'

VMDKFILE='bin/x86/openwrt-x86-generic-combined-ext2.vmdk'

PROGS_NEEDED='which wget tar patch make VBoxManage rm echo svn cp'

SCRIPTDIR=$(cd `dirname ${0}`; echo `pwd`)



if [ "${UID}" -eq 0 ]; then
  echo "ERROR: Do not run as root!"
  exit 1
fi

# check for needed programs
for PROG in ${PROGS_NEEDED}; do
  which ${PROG} 1> /dev/null 2> /dev/null
  if [ "${?}" -ne 0 ]; then
    echo "Error detecting program \"${PROG}\" which is necessary to run ${0}."
    echo "Please install it or verify that it is in your \$PATH ($PATH)."
    exit 1
  fi
done


function cleanFile() {
  echo
  echo "Deleting \"${FILENAME}\""
  echo
  rm -f ${SCRIPTDIR}/${FILENAME}
}


function cleanDir() {
  echo
  echo "Deleting \"${FILEDIR}\""
  echo
  rm -rf ${SCRIPTDIR}/${FILEDIR}
}


function buildBuilder() {
  # download OpenWrt ImageBuilder
  if [ ! -e ${SCRIPTDIR}/${FILENAME} ]; then 
    wget ${FILEURL}${FILENAME} -O ${SCRIPTDIR}/${FILENAME}
    if [ $? -ne 0 ]; then
      echo
      echo "ERROR: Downloading file."
      echo
      cleanFile
      exit 1
    fi
    if [ `md5sum ${SCRIPTDIR}/${FILENAME} | cut -d " " -f1` != "${MD5SUM}" ]; then
      echo
      echo "ERROR: md5 mismatch!"
      echo
      cleanFile
      exit 2
    fi
  fi

  if [ ! -d ${SCRIPTDIR}/${FILEDIR} ]; then
    tar xfj ${SCRIPTDIR}/${FILENAME} -C ${SCRIPTDIR}/
    if [ $? -ne 0 ]; then
      echo
      echo "ERROR: Extracting file."
      echo
      cleanDir
      exit 1
    fi
    cd ${SCRIPTDIR}/${FILEDIR}
    for i in ../patches/imagebuilder/*; do
      patch -p1 -i ${i} 
      if [ $? -ne 0 ]; then
        echo
        echo "ERROR: Applying patch."
        echo
        cleanDir
        exit 1
      fi
    done
    cd ${SCRIPTDIR}
  fi
}


function buildDisk() {
  # build image
  cd ${SCRIPTDIR}/${FILEDIR}
  make -j${BUILD_THREADS} image PROFILE="torgw" FILES="../overlay" 
  if [ $? -eq 0 ]; then
    echo
    echo
    echo "-----------------------------------------------------------------------------------"
    echo "VM disk image created: \"${SCRIPTDIR}/${FILEDIR}/${VMDKFILE}\""
    echo "-----------------------------------------------------------------------------------"
    echo
    echo
  else
    echo
    echo "ERROR: Creating image."
    echo
    exit 1
  fi
  cd ${CWD} 
}


function cleanVM() {
  echo
  echo "Deleting VM."
  echo
  VBoxManage unregistervm "${NAME}" --delete
}


function cleanOVA() {
  echo
  echo "Deleting ova file."
  echo
  rm -f "${SCRIPTDIR}/${NAME}.ova"
}


function cleanSource() {
  echo
  echo "Deleting source files."
  echo
  rm -rf "${SCRIPTDIR}/backfire_10.03.1"
}


# create vm
function createVM() {
  if [ ! -e ${SCRIPTDIR}/${FILEDIR}/${VMDKFILE} ]; then
    echo
    echo "ERROR: Disk file \"${SCRIPTDIR}/${FILEDIR}/${VMDKFILE}\" not found."
    echo
    exit 1
  fi
    
  VBoxManage createvm --name "${NAME}" --ostype "Linux26" --register
  if [ $? -ne 0 ]; then
    echo
    echo "ERROR: Creating VM."
    echo
    cleanVM
    exit 1
  fi
  
  # configure vm
  VBoxManage modifyvm "${NAME}" --memory "48" --boot1 "disk" --boot2 "none" \
  --boot3 "none" --boot4 "none" --vram "1" --nic1 "nat" --nictype1 "82543GC" \
  --nic2 "intnet" --nictype2 "82543GC" --intnet2 "tor" --biosbootmenu "disabled" \
  --rtcuseutc "on" --clipboard "disabled"
  if [ $? -ne 0 ]; then
    echo
    echo "ERROR: Configuring VM."
    echo
    cleanVM
    exit 1
  fi

  # add ide controller to vm
  VBoxManage storagectl "${NAME}" --name "IDE Controller" --add ide --controller ICH6
  if [ $? -ne 0 ]; then
    echo
    echo "ERROR: Adding storage controller to VM."
    echo
    cleanVM
    exit 1
  fi

  # add disk to vm
  VBoxManage storageattach "${NAME}" --storagectl "IDE Controller" --port 0 \
  --device 0 --type hdd --medium "${SCRIPTDIR}/${FILEDIR}/${VMDKFILE}"
  if [ $? -ne 0 ]; then
    echo
    echo "ERROR: Adding disk to VM."
    echo
    cleanVM
    exit 1
  fi

  # export vm to ova file
  if [ -f "${SCRIPTDIR}/${NAME}.ova" ]; then
    cleanOVA
  fi
  VBoxManage export "${NAME}" --output "${SCRIPTDIR}/${NAME}.ova" --vsys 0 \
  --version "${VERSION}" --vendor "ra" --vendorurl "https://ra.fnord.at/"
  if [ $? -ne 0 ]; then
    echo
    echo "ERROR: Exporting VM."
    echo
    cleanVM
    exit 1
  fi
  echo
  echo
  echo "-----------------------------------------------------------------------------------"
  echo "${NAME} created: \"${SCRIPTDIR}/${NAME}.ova\""
  echo "-----------------------------------------------------------------------------------"
  echo
  echo

  # delete vm
  VBoxManage storagectl "${NAME}" --name  "IDE Controller" --remove
  if [ $? -ne 0 ]; then
    echo
    echo "ERROR: Deleting storage controller from VM."
    echo
    cleanVM
    exit 1
  fi
  UUID=`VBoxManage showhdinfo ${SCRIPTDIR}/${FILEDIR}/${VMDKFILE} | egrep '^UUID:' | awk '{print $2}'`
  VBoxManage closemedium disk ${UUID} --delete
  if [ $? -ne 0 ]; then
    echo
    echo "ERROR: Deleting disk from VM."
    echo
    cleanVM
    exit 1
  fi
  cleanVM
}


# compile tor and tor-geoip packages
function compileTor() {
  cd ${SCRIPTDIR}

  if [ ! -d backfire_10.03.1 ]; then
    svn co svn://svn.openwrt.org/openwrt/tags/backfire_10.03.1/
    if [ $? -ne 0 ]; then
      echo
      echo "ERROR: Checking out source code from SVN."
      echo
      exit 1
    fi
  fi

  cd backfire_10.03.1

  # update package feeds
  ./scripts/feeds update -a
  if [ $? -ne 0 ]; then
    echo
    echo "ERROR: Updating feeds."
    echo
    exit 1
  fi


  # update package feeds
  ./scripts/feeds install -a
  if [ $? -ne 0 ]; then
    echo
    echo "ERROR: Installing feeds."
    echo
    exit 1
  fi


  # copy config file
  cp -ap ../OpenWrt-ImageBuilder-x86-for-Linux-i686/.config . 
  if [ $? -ne 0 ]; then
    echo
    echo "ERROR: Copying config file."
    echo
    exit 1
  fi


  # build toolchain
  make -j${BUILD_THREADS} prepare 
  if [ $? -ne 0 ]; then
    echo
    echo "ERROR: Preparing OpenWRT build environment."
    echo
    exit 1
  fi


  # apply patches and ignore if already applied
  for i in ../patches/source/*; do
    patch -p1 -t -i ${i} 
  done


  # build tor and tor-geoip packages
  make -j${BUILD_THREADS} package/tor/{clean,compile,install} 
  if [ $? -ne 0 ]; then
    echo
    echo "ERROR: Compiling tor package."
    echo
    exit 1
  fi


  # copy tor and tor-geoip packages to ImageBuilder directory
  cp ./bin/x86/packages/tor*_x86.ipk ../OpenWrt-ImageBuilder-x86-for-Linux-i686/packages/
  if [ $? -ne 0 ]; then
    echo
    echo "ERROR: Copying tor package."
    echo
    exit 1
  fi

  cd .. 
}


function usage() {
  echo "Usage: ${0} [clean|help]"
  exit 1
}


if [ $# -eq 0 ]; then
  buildBuilder
  compileTor
  buildDisk
  createVM
elif [ $# -eq 1 ]; then
  if [ ${1} = 'clean' ]; then
    cleanDir
    cleanFile
    cleanSource
    cleanOVA
  elif [ ${1} = 'help' ]; then
    usage
  else
    ${1}
  fi
else
  usage
fi

