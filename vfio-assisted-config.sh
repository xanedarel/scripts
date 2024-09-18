#!/bin/bash

#checking dracut configuration folders and the status of a vfio.conf file
dirdracut=/etc/dracut.conf.d; ! [[ -d "$dirdracut" ]] && echo "Script obsolete review dracut.conf.d" && exit || echo "Dracut configuration folder found;"
confvfio=$(ls $dirdracut | grep vfio);
if [ -z $confvfio ]; then
echo "No prior vfio configuration found, setting up $dirdracut/20-vfio.conf (this requires running the script as root)"
touch $dirdracut/20-vfio.conf
echo "Adding the following line to $dirdracut/20-vfio.conf"
echo "force_drivers+=\" vfio_pci vfio vfio_iommu_type1 \"" | tee $dirdracut/20-vfio.conf
else
echo "existing vfio configuration found $confvfio"
fi
function iommuscript {
## iommu script from https://wiki.archlinux.org/title/PCI_passthrough_via_OVMF#Enabling_IOMMU
# change the 999 if needed
shopt -s nullglob
for d in /sys/kernel/iommu_groups/{0..999}/devices/*; do
    n=${d#*/iommu_groups/*}; n=${n%%/*}
    printf 'IOMMU Group %s ' "$n"
    lspci -nns "${d##*/}"
done;
##
}

#detecting vfio use on VGA and skipping configuration wip
#varvheckvfio=$(lspci -k | grep vfio); ! [[ -z varvheckvfio ]] && echo "Found vfio driver in use, skip configuration? [y/n]"
#read varskip

#gpu autodetection wip
#function awkprint {
#awk -F ']' '{print$1}' | awk -F '[' '{print$2}'
#}
#vga=$(lspci | grep VGA | awkprint)
! [[ -z $vga ]] && echo -e "The following GPUs have been found:\n$vga" || echo "Autodetection failed : Please enter your GPU manufacturer [Press enter for unknown]"

#get pci.ids values from the IOMMU group of target gpu pci device
read vargpumkr
if [ -z $vargpumkr ]; then
echo "No manufacturer entered, displaying all IOMMU groups :" && wait 2; iommuscript
else
iommuscript | grep -i $vargpumkr
fi
echo "Please enter the IOMMU group which you would like to passthrough:"
read -p "IOMMU GROUP "  vargroup
vargroupids=$(iommuscript | grep "IOMMU Group $vargroup" | grep -o "[0-9A-Za-z][0-9A-Za-z][0-9A-Za-z][0-9A-Za-z]:[0-9A-Za-z][0-9A-Za-z][0-9A-Za-z][0-9A-Za-z]")

#creating array of pci ids
varids=()
for i in $vargroupids; do
count=$((count + 1))
varids+=($i); done
#check for user agreement
echo "PCI IDS configuration: ${varids[*]}."
read -p "Continue with these settings? [y/n]:" vardoconfig
[[ -z $vardoconfig ]] && echo "no input detected"
[[ -z $vardoconfig || "n" == $vardoconfig ]] && echo "exiting script" && exit
#setting the array to be writable to /etc/default/grub
varwriteids=$(echo ${varids[*]} | sed "s/ /,/g")
#Appending the ids to /etc/default/grub GRUB_CMDLINE_LINUX_DEFAULT line (requires root access)
sed -i "/^GRUB_CMDLINE_LINUX_DEFAULT=/ s/\"$/ vfio-pci.ids=$varwriteids\"/" /etc/default/grub
echo "#Running update-grub"
update-grub
