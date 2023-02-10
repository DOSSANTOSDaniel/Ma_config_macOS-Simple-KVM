#!/bin/bash

set -eu

# test de l'utilisateur
if [[ $(id -u) -eq 0 ]]
then
  echo "Ne pas lancer le script en tant que root !"
  exit 0
fi

# Choix d'un disque externe d'installation
PS3="Votre choix : "
mapfile -t USBDEVICES < <(ls -l /dev/disk/by-id/* | grep -vE "[[:digit:]]$" | awk -F ' /' '{print "/"$2}')

echo -e "\n ----- Informations complémentaires sur les disques ----- "
lsblk -ld -I 8 -o NAME,TYPE,SIZE,MODEL
echo -e "-------------------------------- \n"

echo " ----- Menu des différents liens vers les disques ----- "
select ITEM in "${USBDEVICES[@]}" 'Quitter'
do
  if [[ $ITEM == 'Quitter' ]]
  then
    echo "Fin du programme!"
    exit 0
  fi
  break
done

IDHOSTUSER="$(id -u)"
HOSTUSER="$(id -u $IDHOSTUSER -n)"
PHYSICALDISK="$(echo $ITEM | awk '{print $1}')"
sudo chown ${HOSTUSER}:${HOSTUSER} $PHYSICALDISK

OSK="ourhardworkbythesewordsguardedpleasedontsteal(c)AppleComputerInc"
VMDIR=$PWD
OVMF=${VMDIR}/firmware

# RAM
PCRAM="$(grep 'MemTotal' /proc/meminfo | awk '{print $2}')"
VMRAM="$(echo "scale = 10;ram=${PCRAM};ram/=1024;ram/=1024;ram/=2;ram" | bc | awk '{printf("%d\n",$1 + 0.5)}')G"

# CPU
CPUTHREADS="$(lscpu | grep 'Thread(s)' | awk '{print $4}')"
CPUCORES="$(lscpu | grep 'Cœur(s)' | awk '{print $4}')"
CPUSOCKETS="$(lscpu | grep 'Socket(s)' | awk '{print $2}')"
TOTALTHREADS="$((CPUTHREADS * CPUCORES * CPUSOCKETS))"
CPUOPTIONS=',+kvm_pv_unhalt,+kvm_pv_eoi,+hypervisor,+invtsc,+pcid,+ssse3,+sse4.2,+popcnt,+avx,+avx2,+aes,+fma,+fma4,+bmi1,+bmi2,+xsave,+xsaveopt,+sse3,+xsavec,+xgetbv1,+smep,+movbe,check'

# Audio, ex: pa,alsa,jack,oss,sdl,none
QEMUAUDIO='pa'
QEMUAUDIOSERVER="/run/user/${IDHOSTUSER}/pulse/native" 

# Port SSH : ssh -p 2222 user@127.0.0.1
HOSTSSHPORT='2222'

clear

cat << EOF
       ___ Script  : $(basename ${0}) ___
       
  ----------------- Résumé -----------------
  ------------------------------------------
  
  Utilisateur : $HOSTUSER
  
  Disque : $PHYSICALDISK
  
  RAM : $VMRAM
  
  CPU_Threads : $CPUTHREADS
  CPU_Cores : $CPUCORES
  CPU_Sockets : $CPUSOCKETS
  CPU_Total_Threads : $TOTALTHREADS
  
  AUDIO_Device : $QEMUAUDIO
  AUDIO_Server : $QEMUAUDIOSERVER
  
  Connexion SSH : ssh -p 2222 <USER>@127.0.0.1  
  
  
  
EOF

read -p "Appuyez sur Entrée pour continuer ! "

qemu-system-x86_64 \
    -m ${VMRAM} \
    -machine q35,accel='kvm' \
    -smp ${TOTALTHREADS:='4'},threads="${CPUTHREADS:='2'}",cores="${CPUCORES:='2'}",sockets="${CPUSOCKETS:='1'}" \
    -cpu Penryn,kvm='on',vendor='GenuineIntel'${CPUOPTIONS} \
    -device isa-applesmc,osk="$OSK" \
    -smbios type='2' \
    -object rng-random,id='rng0',filename='/dev/urandom' -device virtio-rng-pci,rng='rng0' \
    -serial mon:stdio \
    -drive if='pflash',format='raw',readonly='on',file="${OVMF}/OVMF_CODE.fd" \
    -drive if='pflash',format='raw',file="${OVMF}/OVMF_VARS-1024x768.fd" \
    -display sdl,window-close=on \
    -device qxl-vga \
    -k fr \
    -L /usr/share/seabios/ \
    -L /usr/lib/ipxe/qemu/ \
    -L /usr/share/qemu/ \
    -audiodev ${QEMUAUDIO},id="$QEMUAUDIO",server="$QEMUAUDIOSERVER" \
    -device ich9-intel-hda \
    -device hda-duplex,audiodev="$QEMUAUDIO" \
    -usb -device usb-kbd -device usb-mouse -device usb-tablet \
    -netdev user,id='net0',hostfwd="tcp:127.0.0.1:${HOSTSSHPORT}-:22" \
    -device vmxnet3,netdev='net0',id='net0' \
    -device ich9-ahci,id='sata' \
    -drive id='ESP',if='none',format='qcow2',file='ESP.qcow2' \
    -device ide-hd,bus='sata.2',drive='ESP' \
    -drive id='InstallMedia',format='raw',if='none',file='BaseSystem.img' \
    -device ide-hd,bus='sata.3',drive='InstallMedia' \
    -drive id='SystemDisk',if='none',file="$PHYSICALDISK",format='raw',media='disk' \
    -device ide-hd,bus='sata.4',drive='SystemDisk' &
