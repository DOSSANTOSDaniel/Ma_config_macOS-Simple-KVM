# Temp

## Mise en place de passthrough USB
```bash
# Mise en place de passthrough USB
read -p "Voulez-vous connecter une clé USB ? [o/n]" REPUSB
read -p "brancher votre clé USB puis appuyez sur Entrée ! "

if [[ "$REPUSB" == "o" ]]
then
  read -p "Brancher votre clé USB puis appuyez sur Entrée ! "

  PS3="Votre choix : "
  mapfile -t USBDEVICES2 < <(lsusb | awk '{for(i=6;i<=NF;i++) printf $i" "; print ""}')

  echo -e "\n -- Menu USB -- "
  select ITEM in "${USBDEVICES2[@]}" 'Quitter'
  do
    if [[ $ITEM == 'Quitter' ]]
    then
      echo "Fin du programme!"
      exit 0
    fi
    break
  done

  VENDORID="0x$(echo "$ITEM" | awk '{print $1}' | cut -d':' -f1)"
  PRODUCTID="0x$(echo "$ITEM" | awk '{print $1}' | cut -d':' -f2)"
  
  USB_OPTION="-device usb-ehci,id=ehci -device usb-host,vendorid=$VENDORID,productid=$PRODUCTID"
fi
```

## Mise en place de passthrough CPIe
```bash

```
