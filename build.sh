#!/bin/sh

# Purpose: Build Tor gateway image and create VirtualBox VM
# by ra (2012)

VERSION="0.5.0"
NAME="Tor gateway ${VERSION}"
BUILD_THREADS='3'

FILENAME='OpenWrt-ImageBuilder-x86-for-Linux-i686.tar.bz2'
FILEURL='http://backfire.openwrt.org/10.03.1/x86_generic/'
FILEDIR='OpenWrt-ImageBuilder-x86-for-Linux-i686'
MD5SUM='c4f75b9f2350db7cfae0d5299688b8ff'

VMDKFILE='bin/x86/openwrt-x86-generic-combined-ext2.vmdk'

PROGS_NEEDED='which wget tar patch make VBoxManage rm echo'

# check for needed programs
for PROG in ${PROGS_NEEDED}; do
  which ${PROG} 1> /dev/null 2> /dev/null
  if [ "${?}" -ne 0 ]; then
    echo "Error detecting program \"${PROG}\" which is necessary to run ${0}."
    echo "Please install it or verify that it is in your \$PATH ($PATH)."
    exit 1
  fi
done

SCRIPTDIR=`dirname ${0}`


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


function buildDisk() {
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
    CWD=`pwd` 
    cd ${SCRIPTDIR}/${FILEDIR}
    for i in ../patches/*; do
      patch -p1 -i ${i} 
      if [ $? -ne 0 ]; then
        echo
        echo "ERROR: Applying patch."
        echo
        cleanDir
        exit 1
      fi
    done
    cd ${CWD} 
  fi

  # build image
  CWD=`pwd` 
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
  VBoxManage modifyvm "${NAME}" --memory "32" --boot1 "disk" --boot2 "none" \
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
  echo
  echo
  echo "-----------------------------------------------------------------------------------"
  echo "${NAME} created: \"${SCRIPTDIR}/${NAME}.ova\""
  echo "-----------------------------------------------------------------------------------"
  echo
  echo

  # delete vm
  VBoxManage storagectl "${NAME}" --name  "IDE Controller" --remove
  UUID=`VBoxManage showhdinfo ${SCRIPTDIR}/${FILEDIR}/${VMDKFILE} | egrep '^UUID:' | awk '{print $2}'`
  VBoxManage closemedium disk ${UUID} --delete
  cleanVM
}


if [ $# -eq 0 ]; then
  buildDisk
  createVM
elif [ ${1} = 'disk' -a $# -eq 1 ]; then
  buildDisk
elif [ ${1} = 'vm' -a $# -eq 1 ]; then
  createVM
elif [ ${1} = 'clean' -a $# -eq 1 ]; then
  cleanDir
  cleanFile
  cleanOVA
else
  echo "Usage: ${0} [disk|vm|clean]"
  exit 1
fi

