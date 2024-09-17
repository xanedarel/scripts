#!/bin/bash

#checking dracut configuration folders and the status of a vfio.conf file
dirdracut=/etc/dracut.conf.d/; ! [[ -d "$dirdracut" ]] && echo "script obsolete review dracut.conf.d" && exit || echo "dracut configuration folder found"
confvfio=$(ls $dirdracut | grep vfio); [[ -z $confvfio ]] && echo "no prior vfio configuration found" || echo "existing vfio configuration found $confvfio"

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
#varvheckvfio=$(lspci -k | grep vfio); ! [[ -z varvheckvfio ]] && echo "Found vfio driver in use, skipping configuration"

#gpu autodetection wip
#function awkprint {
#awk -F ']' '{print$1}' | awk -F '[' '{print$2}'
#}
#vga=$(lspci | grep VGA | awkprint)
! [[ -z $vga ]] && echo -e "The following GPUs have been found:\n$vga" || echo "Autodetection failed : Please enter your GPU manufacturer [Press enter for unknown]"

#
read vargpumkr
if [ -z $vargpumkr ] || [ -z $vga ]; then
echo "No manufacturer entered, displaying all IOMMU groups :" && wait 2 && iommuscript
else
echo $(iommuscript | grep -i $vargpumkr)
fi
echo "Please enter the IOMMU group which you would like to passthrough:"
read -p "IOMMU GROUP "  vargroup
vargroupids=iommuscript | grep "IOMMU Group $vargroup" | grep -o "[[0-9A-Za-z][0-9A-Za-z][0-9A-Za-z][0-9A-Za-z]:[0-9A-Za-z][0-9A-Za-z][0-9A-Za-z][0-9A-Za-z]]"

#end config wip
#write pci.ids to $confvfio
#dracut -f 
#sed -i 's/CMD_LINUX_DEFAULT=/""vfio-pci.ids=[ids]/g' /etc/default/grub
#update-grub
