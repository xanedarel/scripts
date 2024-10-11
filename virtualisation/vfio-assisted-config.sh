#!/bin/bash

# This script aims to automate the configuration needed to use the vfio drivers
# on specific pci devices / iommu group. The sources for third party code have
# been explicited. Some actions require elevated privileges, like setting up
# $DIRDRACUT/20-vfio.conf, regenerating the initramfs, configuring the
# vfio-pci.ids on GRUB, and updating the grub. The script is heavily influenced
# by the use of NVIDIA GPUs, please help make it more manufacturer agnostic.

#             Always read a script you download from the internet.             #

##checking dracut configuration folders and the status of a vfio.conf file

DIRDRACUT=/etc/dracut.conf.d
if [[ ! -d "$DIRDRACUT" ]]; then
    echo "Script obsolete review dracut.conf.d"
    exit
else
    echo "Dracut configuration folder found;"
fi

CONFVFIO=$(ls $DIRDRACUT | grep vfio);

if [ -z "$CONFVFIO" ]; then
    echo "No prior vfio configuration found, setting up $DIRDRACUT/20-vfio.conf (this requires running the script as root)"
    touch $DIRDRACUT/20-vfio.conf; echo "Adding the following line to $DIRDRACUT/20-vfio.conf"
    echo "force_drivers+=\" vfio_pci vfio vfio_iommu_type1 \"" | tee $DIRDRACUT/20-vfio.conf
    read -p "Regenerate initramfs now? [y/n]:" vargen; [[ "y" == "$vargen" ]] && dracut -f;
else
    echo "Existing vfio configuration found: $DIRDRACUT/$CONFVFIO"
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
    echo "No manufacturer entered, displaying all IOMMU groups:" && wait 2
    iommuscript
else
    displaygroups=$(iommuscript | grep -i "$vargpumkr")
    [[ -n "$displaygroups" ]] && echo "$displaygroups" || echo -e "No match found, displaying all IOMMU groups:\n" || iommuscript
fi
echo "Please enter the IOMMU group which you would like to passthrough:"
read -p "IOMMU GROUP "  vargroup

##creating array of pci ids
arids=(); grepids="[0-9A-Za-z]\{4\}:[0-9A-Za-z]\{4\}"; countarids=0
for i in $(iommuscript | grep "IOMMU Group $vargroup" | grep -o "$grepids"); do countarids=$((countarids + 1)); arids+=($i); done

##write changes
#check for user agreement

echo "PCI IDs configuration: ${arids[*]}."
read -p "Continue with these settings? [y/n]:" vardoconfig
[[ ! "$vardoconfig" =~ ^[yY]$ ]] && echo "exiting script" && exit
#modify the array to fit the kernel's command line syntax
varwriteids=$(echo ${arids[*]} | sed "s/ /,/g")
#check wether /etc/default/grub already has pci.ids entries (todo: make sure to read from the "GRUB_CMDLINE_LINUX_DEFAULT=" line)
if [[ -f $(which grub 2>/dev/null) ]]; then
        vargrubvfio=$(grep -o "$grepids" /etc/default/grub)
    if [ -z "$vargrubvfio" ] ; then
        echo "Appending the ids to /etc/default/grub GRUB_CMDLINE_LINUX_DEFAULT line (requires root privileges)"
        sed -i "/^GRUB_CMDLINE_LINUX_DEFAULT=/ s/\"$/ vfio-pci.ids=$varwriteids\"/" /etc/default/grub
        read -p "Run update-grub now? [y/n]:" grubupd
        [[ "$grubupd" =~ ^[yY]$ ]] && update-grub
        else
#Comparing preexisting vfio-pci.ids
        agvfio=(); for i in $vargrubvfio; do countagvfio=$((countagvfio + 1)); agvfio+=($i);done
        for ((i=0; i < "${#varwriteids[@]}"; i++)); do
        # debug echo "i = $i"
        if [[ ! " ${avfio[@]} " =~ "${varwriteids[$i]}" ]]; then
                varwrite+=(${varwriteids[$i]})
                unset varwriteids[$i]
        fi
        done
        #modify the grub wip
        printf "Modifying line:$( grep -Fn 'GRUB_CMDLINE' /etc/default/grub | awk -F ':' '{print $1}') of /etc/default/grub : adding the following ids ${varwrite[@]}"
        read -p "Confirm? [y/n]" vargrub
        [[ "$vargrub" =~ ^[yY]$ ]] && sed -i "/^GRUB_CMDLINE_LINUX_DEFAULT=/ s/vfio-pci.ids=//g" /etc/default/grub
    fi
#gummiboot support WIP
elif [[ -f $(which gummiboot 2>/dev/null) ]]; then
    #determining what folder gummiboot uses
    [[ -d /boot/loader/ ]] && loader=/boot/loader
    [[ -d /efi/loader/ ]] && loader=/efi/loader
    #getting the default .conf file
    [[ -f $loader/loader.conf ]] && defaultboot=$(awk '{print $2}' $loader/loader.conf)
    cp $loader/entries/$defaultboot.conf $loader/entries/$defaultboot.back
    [[ -z $(grep -i options $loader/entries/$defaultboot.conf) ]] && echo "options" >> $loader/entries/$defaultboot.conf
    if [ -z $(grep -i "[0-9A-Za-z]\{4\}:[0-9A-Za-z]\{4\}") ]; then
    sed -i "/^options/ s/\$/ vfio-pci.ids=$varwriteids/" $loader/entries/$defaultboot.conf
    else

    echo "Modified $loader/entries/$defaultboot.conf"
fi
