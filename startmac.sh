#!/bin/bash
#-*- coding: UTF8 -*-

#--------------------------------------------------#
# Script_Name: startmac.sh	                               
#                                                   
# Date: mer. 15 févr. 2023 21:17                                             
# Version: 1.0                                      
# Bash_Version: 5.1.16(1)-release                           
#--------------------------------------------------#
#
# Usage: ./startmac.sh [-h|i]
#    
# Option 1: ./startmac.sh        Démarrage de la machine virtuelle.
# Option 2: ./startmac.sh -i     Télécharge macOS-Simple-KVM et l'image d'installation de macOS, puis démarre la machine virtuelle.
# Option 3: ./startmac.sh -h     Affiche l'aide.
#                                                                          
#--------------------------------------------------#

set -eu

## Fonctions
Usage() {
  cat << USAGE

    Usage: ${0} [-h|i]
    
    Option 1: ${0}        Démarrage de la machine virtuelle.
    Option 2: ${0} -i     Télécharge macOS-Simple-KVM et l'image d'installation de macOS, puis démarre la machine virtuelle.
    Option 3: ${0} -h     Affiche l'aide.

USAGE
  exit 0
}

# Install dependances
InstallDep() {
  echo "Téléchargement et installation des dépendances en cours ..."
  if [[ "$OSTYPE" == 'linux-gnu' ]]
  then
    if (command -v apt-get 2> /dev/null)
    then
      for APPINSTALL in 'qemu-system-x86' 'qemu-utils' 'python3' 'python3-pip' 'bc' 'git'
      do
        if ! (dpkg -L "${APPINSTALL}" 2> /dev/null)
        then
          sudo apt-get update -qq
          if ! (sudo apt-get install ${APPINSTALL} -qqy)
          then
            echo "'ERREUR' Installation de ${APPINSTALL} Impossible!"
            exit 1
          fi
        fi
      done
    elif (command -v dnf 2> /dev/null)
    then
      for APPINSTALL in 'qemu' 'qemu-img' 'python3' 'python3-pip' 'bc' 'git'
      do  
        if ! (rpm -ql ${APPINSTALL} 2> /dev/null)
        then  
          sudo dnf check-update --quiet
          if ! (sudo dnf install --quiet --assumeyes ${APPINSTALL})
          then
            echo "'ERREUR' Installation de ${APPINSTALL} Impossible!"
            exit 1
          fi
        fi
      done
    elif (command -v pacman 2> /dev/null)
    then
      for APPINSTALL in 'qemu' 'python' 'python-pip' 'python-wheel' 'bc' 'git'
      do  
        if ! (pacman -Ql ${APPINSTALL} 2> /dev/null)
        then
          sudo pacman -Sy --quiet 
          if ! (sudo pacman -S ${APPINSTALL} --quiet --noconfirm --noprogressbar)
          then
            echo " 'ERREUR' Installation de ${APPINSTALL} Impossible!"
            exit 1
          fi
        fi
      done
    else
      echo -e "\n Gestionnaire de paquets non prit en charge."
      echo -e "Merci d'installer ${APPINSTALL} manuellement. \n"
      exit 1
    fi
  else
    echo -e "\n Système non prit en charge. \n"
    exit 1
  fi
}

# Download macOS-Simple-KVM
DownloadMacSimple() {
  if ! [[ -d ${MSKDIR} ]]
  then
    if ! (git clone https://github.com/foxlet/macOS-Simple-KVM.git)
    then
      echo " 'ERREUR' Téléchargement de https://github.com/foxlet/macOS-Simple-KVM.git Impossible!"
      exit 1
    fi
  fi
}

# Choice of macOS version : high-sierra, mojave or catalina
DownloadMacVersion() {
  PS3="Votre choix : "
  clear
  echo " ----- Menu macOS versions ----- "
  echo
  select ITEM in 'high-sierra' 'mojave' 'catalina' 'Quitter'
  do
    if [[ $ITEM == 'Quitter' ]]
    then
      echo "Fin du programme!"
      exit 0
    fi
    break
  done

  MACVER="$ITEM"

  cd $MSKDIR
  # Download installation image
  ./jumpstart.sh --${MACVER}
  date +%c >> ${MSKPDIR}/installversion.log
  echo "macOS $MACVER" >> ${MSKPDIR}/installversion.log
  echo "###" >> ${MSKPDIR}/installversion.log
  
  BANVERSIONMAC="Version :----------------: macOS $MACVER"
  
  read -p "Voulez vous installer macOS $MACVER sur le disque maintenant [o/n] ? : " CHECKIFINSTALL
  if ! [[ $CHECKIFINSTALL =~ ^(o|O|)$ ]]
  then
    echo "Fin du programme"
    exit 1
  fi
}

### Main ###

## Global variables
# Installation directory
MSKPDIR="$(pwd)"
MSKDIR="${MSKPDIR}/macOS-Simple-KVM"

# User
IDHOSTUSER="$(id -u)"
HOSTUSER="$(id -u $IDHOSTUSER -n)"

# Banner
BANVERSIONMAC='...'
BANDESCRIPTIONDEVICE='...'
BANUSBHOSTBUS='...'
BANUSBHOSTPORT='...'

# Audio, ex: pa,alsa,jack,oss,sdl,none
QEMUAUDIO='pa'
QEMUAUDIOSERVER="/run/user/${IDHOSTUSER}/pulse/native" 

# Port SSH : ssh -p 2222 user@127.0.0.1
HOSTSSHPORT='2222'
USB_OPTION=" "

# BIOS
OSK='ourhardworkbythesewordsguardedpleasedontsteal(c)AppleComputerInc'
VMDIR=$MSKDIR
OVMF=${VMDIR}/firmware

# RAM
PCRAM="$(grep 'MemTotal' /proc/meminfo | awk '{print $2}')"
VMRAM="$(echo "scale = 10;ram=${PCRAM};ram/=1024;ram/=1024;ram/=2;ram" | bc | awk '{printf("%d\n",$1 + 0.5)}')G"

# CPU
MODELCPU="$(lscpu | grep -E 'Model name|Nom de modèle' | tr -s " " | cut -d " " -f4-)"
CPUTHREADS="$(lscpu | grep -E 'Thread\(s\) per core|Thread\(s\) par cœur' | awk '{print $4}')"
CPUCORES="$(lscpu | grep -E 'Core\(s\) per socket|Cœur\(s\) par socket' | awk '{print $4}')"
CPUSOCKETS="$(lscpu | grep 'Socket(s)' | awk '{print $2}')"
TOTALTHREADS="$((CPUTHREADS * CPUCORES * CPUSOCKETS))"
CPUOPTIONS='+kvm_pv_unhalt,+popcnt,+kvm_pv_eoi,+hypervisor,vmware-cpuid-freq=on,+invtsc,+pcid,+ssse3,+sse4.2,+avx,+avx2,+aes,+fma,+fma4,+bmi1,+bmi2,+xsave,+xsaveopt,+sse3,+xsavec,+xgetbv1,+smep,+movbe,check'

## Tests
# Check user
if [[ $(id -u) -eq 0 ]]
then
  clear
  echo -e "\n Ne pas lancer le script en tant que root ! \n"
  exit 0
fi

# Checking if virtualization is supported
if [[ $(grep -Ec '(vmx|svm)' /proc/cpuinfo) -gt 0 ]]
then
  echo "Virtualisation supportée!"
else
  echo "La virtualisation n'est pas supportée sur ce système !"
  echo "Activer la technologie de virtualisation (VTx) dans le BIOS"
  exit 1
fi

readonly PARAM="iuh"
while getopts "${PARAM}" PARG
do
  case "${PARG}" in
    h)
      clear
      Usage
      ;;
    i)
      InstallDep
      DownloadMacSimple
      if [[ -f ${MSKDIR}/BaseSystem.img ]]
      then
        clear
        cat ${MSKPDIR}/installversion.log
        echo -e "\n Une image d'installation existe déjà !"
        echo " Pour télécharger une nouvelle image, il faut placer le script ${0} dans un répertoire différent, puis lancer le téléchargement."
        echo -e " Si non vous pouvez écraser l'image actuelle pour télécharger la nouvelle. \n"
        read -p "Voulez vous écraser l'image actuelle ? [o/n] : " REPERASE
        if [[ $REPERASE =~ ^(o|O|)$ ]]
        then
          DownloadMacVersion
        else
          echo "Fin du programme"
          exit 1
        fi
      else
        DownloadMacVersion
      fi
      ;;
    *)
      echo "Option non valide !"
      ;;
  esac
done

if [[ -d $MSKDIR ]]
then
  cd $MSKDIR
else
  clear
  echo -e "\n Le dossier $MSKDIR n'existe pas !"
  echo -e " Il faut faire une installation : ${0} -i \n"
  Usage
fi

# Choosing a physical disk
read -p "Brancher votre disque puis appuyez sur Entrée ! "

PS3="Votre choix : "
mapfile -t USBDEVICES < <(lsblk -l --noheadings --perms --nodeps --exclude 7 --output NAME,SIZE,TRAN,SERIAL,MODEL)
clear
echo " ----- Menu disques ----- "
echo
echo "   NAME   SIZE TRAN   SERIAL       MODEL"
select ITEM in "${USBDEVICES[@]}" 'Quitter'
do
  if [[ $ITEM == 'Quitter' ]]
  then
    echo "Fin du programme!"
    exit 0
  fi
  break
done

# Check if the disk is in use by the system
INFODISK="$ITEM"
NAMEDISK="$(echo $ITEM | awk '{print $1}')"

mapfile -t LISTMOUNTDISK < <(findmnt --fstab --evaluate --noheadings | awk '{print $2}' | tr -d "[:digit:]" | uniq)

for MOUNTDISK in "${LISTMOUNTDISK[@]}"
do
  if [[ "$MOUNTDISK" = "/dev/${NAMEDISK}" ]]
  then
    echo "Attention disque en cours d'utilisation par le système !"
    exit 1
  fi
done

# Get name disk by ID
mapfile -t IDDISK < <(ls -l /dev/disk/by-id/*)

for testname in "${IDDISK[@]}"
do
  if [[ "$testname" = *${NAMEDISK} ]] && [[ "$testname" = *wwn* ]]
  then
    PHYSICALDISK="$(echo $testname | awk '{print $9}')"
    break
  else
    if [[ "$testname" = *${NAMEDISK} ]]
    then
      PHYSICALDISK="$(echo $testname | awk '{print $9}')"
    fi
  fi
done

if [[ -z $PHYSICALDISK ]]
then
  PHYSICALDISK="/dev/$NAMEDISK"
fi

# Set disk permissions
set +e
sudo umount /dev/${NAMEDISK}*
set -e 
sudo chown ${HOSTUSER}:${HOSTUSER} $PHYSICALDISK

clear

cat << EOF

           ___ $(basename ${0}) ___
       
  ----------------- Résumé -----------------
  ------------------------------------------
  
  Host User :--------------: $HOSTUSER
  
  Host Infos Disk :--------: /dev/${INFODISK}
  
  $BANVERSIONMAC
  
  RAM vm :-----------------: $VMRAM
  
  Host CPU Model :---------: $MODELCPU
  
  Vm CPU Threads :---------: $CPUTHREADS
  Vm CPU_Cores :-----------: $CPUCORES
  Vm CPU_Sockets :---------: $CPUSOCKETS
  Vm CPU_Total_Threads :---: $TOTALTHREADS
  
  Connexion SSH :----------: ssh -p 2222 <USER>@127.0.0.1


EOF

read -p "Appuyez sur Entrée pour continuer ! "

qemu-system-x86_64 \
    -name macos,process='macos' \
    -pidfile ${MSKPDIR}/macos.pid \
    -boot menu=on \
    -enable-kvm \
    -m ${VMRAM} \
    -machine q35,smm=off,vmport=off,accel='kvm' \
    -smp ${TOTALTHREADS:='4'},threads="${CPUTHREADS:='2'}",cores="${CPUCORES:='2'}",sockets="${CPUSOCKETS:='1'}" \
    -global kvm-pit.lost_tick_policy='discard' \
    -global ICH9-LPC.disable_s3='1' \
    -cpu Penryn,kvm='on',vendor='GenuineIntel',${CPUOPTIONS} \
    -device isa-applesmc,osk="$OSK" \
    -smbios type='2' \
    -rtc base='localtime',clock='host',driftfix='slew' \
    -object rng-random,id='rng0',filename='/dev/urandom' \
    -device virtio-rng-pci,rng='rng0' \
    -drive if='pflash',format='raw',readonly='on',file="${OVMF}/OVMF_CODE.fd" \
    -drive if='pflash',format='raw',file="${OVMF}/OVMF_VARS-1024x768.fd" \
    -display gtk,window-close='on',gl="$GLSUPPORT" \
    -device qxl-vga,vgamem_mb='128' \
    -k fr \
    -L /usr/share/seabios/ \
    -L /usr/lib/ipxe/qemu/ \
    -audiodev ${QEMUAUDIO},id="$QEMUAUDIO",server="$QEMUAUDIOSERVER" \
    -device ich9-intel-hda \
    -device hda-duplex,audiodev="$QEMUAUDIO" \
    -usb -device usb-kbd -device usb-tablet \
    -netdev user,id='net0',hostfwd="tcp:127.0.0.1:${HOSTSSHPORT}-:22" \
    -device vmxnet3,netdev='net0',id='net0' \
    -device ich9-ahci,id='sata' \
    -drive id='ESP',if='none',format='qcow2',file='ESP.qcow2' \
    -device ide-hd,bus='sata.2',drive='ESP' \
    -drive id='InstallMedia',format='raw',if='none',file='BaseSystem.img' \
    -device ide-hd,bus='sata.3',drive='InstallMedia' \
    -drive id='SystemDisk',if='none',file="$PHYSICALDISK",format='raw',cache=writeback,media='disk' \
    -device ide-hd,bus='sata.4',drive='SystemDisk' &
