#!/bin/bash

## This script aims to automate the configuration needed to use the vfio drivers on specific pci devices / iommu group.
## The sources for third party code have been explicited
## Some actions require elevated priviledges, like setting up $dirdracut/20-vfio.conf, regenerating the initramfs, configuring the vfio-pci.ids on GRUB, and updating the grub.
## The script is heavily influenced by the use of NVIDIA GPUs, please help make it more manufacturer agnostic.

echo "Always read a script you downloaded from the internet."

##checking dracut configuration folders and the status of a vfio.conf file
dirdracut=/etc/dracut.conf.d; ! [[ -d "$dirdracut" ]] && echo "Script obsolete review dracut.conf.d" && exit || echo "Dracut configuration folder found;"
confvfio=$(ls $dirdracut | grep vfio);
if [ -z $confvfio ]; then
    echo "No prior vfio configuration found, setting up $dirdracut/20-vfio.conf (this requires running the script as root)"
    touch $dirdracut/20-vfio.conf; echo "Adding the following line to $dirdracut/20-vfio.conf"
    echo "force_drivers+=\" vfio_pci vfio vfio_iommu_type1 \"" | tee $dirdracut/20-vfio.conf; dracut -f;
else
    echo "existing vfio configuration found $confvfio"
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

##detecting vfio use on VGA and skipping configuration wip
#varvheckvfio=$(lspci -k | grep vfio); ! [[ -z varvheckvfio ]] && echo "Found vfio driver in use, skip configuration? [y/n]"
#read varskip

##gpu autodetection wip
function awkprint {
awk -F ']' '{print$1}' | awk -F '[' '{print$2}'
}
#vga=$(lspci | grep VGA | awkprint)
! [[ -z $vga ]] && echo -e "The following GPUs have been found:\n$vga" || echo "Autodetection failed : Please enter your GPU manufacturer [Press enter for unknown]"

##get pci.ids values from the IOMMU group of target gpu pci device
read vargpumkr
if [ -z $vargpumkr ]; then
    echo "No manufacturer entered, displaying all IOMMU groups :" && wait 2; iommuscript
else
    iommuscript | grep -i $vargpumkr
fi
echo "Please enter the IOMMU group which you would like to passthrough:"
read -p "IOMMU GROUP "  vargroup
vargvfio="[0-9A-Za-z][0-9A-Za-z][0-9A-Za-z][0-9A-Za-z]:[0-9A-Za-z][0-9A-Za-z][0-9A-Za-z][0-9A-Za-z]"
vargroupids=$(iommuscript | grep "IOMMU Group $vargroup" | grep -o "$gvfio")

##creating array of pci ids
varids=()
for i in $vargroupids; do
    count=$((count + 1))
    varids+=($i)
done
#check for user agreement
echo "PCI IDS configuration: ${varids[*]}."
read -p "Continue with these settings? [y/n]:" vardoconfig
#>\
# This is ugly, don't like it... But don't know how to do it better (yet)
[[ -z $vardoconfig ]] && echo "no input detected"
[[ -z $vardoconfig || "n" == $vardoconfig ]] && echo "exiting script" && exit
#>/
#writting to /etc/default/grub
varwriteids=$(echo ${varids[*]} | sed "s/ /,/g")
vargrubvfio=$(cat /etc/default/grub | grep -o "$gvfio")
if [ -z "$vargrubvfio" ] ; then
    echo "Appending the ids to /etc/default/grub GRUB_CMDLINE_LINUX_DEFAULT line (requires root access)"
    sed -i "/^GRUB_CMDLINE_LINUX_DEFAULT=/ s/\"$/ vfio-pci.ids=$varwriteids\"/" /etc/default/grub
    echo "Running update-grub"
    update-grub
else
    echo "Found preexisting pci.ids config in /etc/default/grub with ids : $vargrubvfio"
fi
