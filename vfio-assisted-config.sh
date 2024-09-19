#!/bin/bash

## This script aims to automate the configuration needed to use the vfio drivers on specific pci devices / iommu group.
## The sources for third party code have been explicited
## Some actions require elevated privileges, like setting up $dirdracut/20-vfio.conf, regenerating the initramfs, configuring the vfio-pci.ids on GRUB, and updating the grub.
## The script is heavily influenced by the use of NVIDIA GPUs, please help make it more manufacturer agnostic.

echo "Always read a script you download from the internet."

##checking dracut configuration folders and the status of a vfio.conf file
dirdracut=/etc/dracut.conf.d; ! [[ -d "$dirdracut" ]] && echo "Script obsolete review dracut.conf.d" && exit || echo "Dracut configuration folder found;"
confvfio=$(ls $dirdracut | grep vfio);
if [ -z "$confvfio" ]; then
    echo "No prior vfio configuration found, setting up $dirdracut/20-vfio.conf (this requires running the script as root)"
    touch $dirdracut/20-vfio.conf; echo "Adding the following line to $dirdracut/20-vfio.conf"
    echo "force_drivers+=\" vfio_pci vfio vfio_iommu_type1 \"" | tee $dirdracut/20-vfio.conf
    read -p "Regenerate initramfs now? [y/n]:" vargen; [[ "y" == "$vargen" ]] && dracut -f;
else
    echo "Existing vfio configuration found $confvfio"
fi

##setting up the iommu script function
# iommu script from https://wiki.archlinux.org/title/PCI_passthrough_via_OVMF#Enabling_IOMMU
function iommuscript {
# change the 999 if needed
shopt -s nullglob
for d in /sys/kernel/iommu_groups/{0..999}/devices/*; do
    n=${d#*/iommu_groups/*}; n=${n%%/*}
    printf 'IOMMU Group %s ' "$n"
    lspci -nns "${d##*/}"
done;
}


##get pci.ids values from the IOMMU group of target gpu pci device
echo "Please enter your GPU manufacturer [Press enter for unknown]"
read vargpumkr
if [ -z "$vargpumkr" ]; then
    echo "No manufacturer entered, displaying all IOMMU groups :" && wait 2; iommuscript
else
    iommuscript | grep -i "$vargpumkr"
fi
echo "Please enter the IOMMU group which you would like to passthrough:"
read -p "IOMMU GROUP "  vargroup
vargrepids="[0-9A-Za-z][0-9A-Za-z][0-9A-Za-z][0-9A-Za-z]:[0-9A-Za-z][0-9A-Za-z][0-9A-Za-z][0-9A-Za-z]"
vargroupids=$(iommuscript | grep "IOMMU Group $vargroup" | grep -o "$vargrepids")

##creating array of pci ids
arids=()
for i in $vargroupids; do count=$((count + 1)); arids+=($i); done

##write changes
#check for user agreement

echo "PCI IDs configuration: ${arids[*]}."
read -p "Continue with these settings? [y/n]:" vardoconfig
[[ -z $vardoconfig || "n" == $vardoconfig ]] && echo "exiting script" && exit
#modify the array to fit grub's syntax
varwriteids=$(echo ${arids[*]} | sed "s/ /,/g")
#check wether /etc/default/grub already has pci.ids entries
vargrubvfio=$(cat /etc/default/grub | grep -o "$vargrepids")
if [ -z "$vargrubvfio" ] ; then
    echo "Appending the ids to /etc/default/grub GRUB_CMDLINE_LINUX_DEFAULT line (requires root privileges)"
    sed -i "/^GRUB_CMDLINE_LINUX_DEFAULT=/ s/\"$/ vfio-pci.ids=$varwriteids\"/" /etc/default/grub
    echo "Running update-grub"
    update-grub
else
else
    agvfio=(); for i in $vargrubvfio; do countagvfio=$((count +1)); agvfio+=($i);done
    #comparing arrays might make the condition expression return a false negative (todo)
    if [[ "${arids[*]}" == "${agvfio[*]}" ]]; then echo "Configuration is already present with desired pci.ids"

#fixing the array issue wip
#for ((i=0; i<=$countarids; i++)); do ! [[ -z $(cat /etc/default/grub | grep ${arids[$i]}) ]] && eval var$i=found; done

    else
    echo "Found discrepency between script pci.ids and grub pci.ids: Grub=$vargrubvfio; Script=${agvfio[*]}"
    fi
fi
