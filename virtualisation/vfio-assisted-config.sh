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
    printf "force_drivers+=\" vfio_pci vfio vfio_iommu_type1 \"" | tee $DIRDRACUT/20-vfio.conf
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
arids=(); vfioids="[0-9A-Za-z]\{4\}:[0-9A-Za-z]\{4\}"
for i in $(iommuscript | grep "IOMMU Group $vargroup" | grep -o "$vfioids"); do arids+=($i); done

echo "PCI IDs configuration: ${arids[*]}."
read -p "Continue with these settings? [y/N]:" vardoconfig
[[ ! "$vardoconfig" =~ ^[yY]$ ]] && echo "exiting script" && exit
#modify the array to fit the kernel's command line syntax
varwriteids=$(echo ${arids[*]} | sed "s/ /,/g")
#check wether /etc/default/grub already has pci.ids entries (todo: make sure to read from the "GRUB_CMDLINE_LINUX_DEFAULT=" line)
#check which bootloader may be installed
if [[ -f $(which grub 2>/dev/null) ]]; then
    BOOT=grub
	IDFILE=/etc/default/grub
elif [[ -f $(which gummiboot 2>/dev/null) ]]; then
    BOOT=gummi
    CONFFILE=/boot/loader/loader.conf
    IDFILE=/boot/loader/entries/$(awk '{print $2}' $CONFFILE).conf
    [[ -z $(grep -oE "options" $IDFILE) ]] && printf "options" >> $IDFILE
fi

#if you have a different bootloader or different configuration, you can override the $IDFILE variable here by uncommenting the following line and including the URI to the file where your pci.ids are written
#IDFILE=/path/to/file

#> setting the pci.ids entries of $IDFILE
for i in $(grep -o "$vfioids" $IDFILE); do
	avfio+=($i)
done
#> For no preexisting config jump to line : x

#DEBUG
#echo "arids ${arids[@]}"
#echo "avfio ${avfio[@]}"

#Comparing those ids with iommuscript's output
#   ardel is an array with ids in the bootloader's config file which do not match the output of this script;
# checking against avfio
for ((i=0; i < "${#avfio[@]}"; i++)); do
    if [[ ! " ${arids[@]} " =~ "${avfio[$i]}" ]];
        then ardel+=(${avfio[$i]})
#removing that id from avfio so that only ids matching with arids remain in it
                unset avfio[$i]
    fi
done
#running that comparison again this time checking whether any entry in arids is already present in the bootloader's config file, if it isn't, it needs to be written and is added to the array arwrite
for ((i=0; i < "${#arids[@]}"; i++)); do
    if [[ ! " ${avfio[@]} " =~ "${arids[$i]}" ]]
        then arwrite+=(${arids[$i]})
    fi
done
#ids in
#       avfio need to remain in the config file
#       ardel need to be deleted
#       arwrite need to be written

## Writing changes
#the $line variable is only set for cosmetic reasons
line=$(grep -En 'GRUB_CMDLINE|options' $IDFILE)
#asking for user input confirmation with detected changes

#DEBUG>
#echo "varwrite ${varwrite[@]}"
#echo "vardel ${ardel[@]}"
#/>
if [[ -n "${varwrite[@]}" ]]; then
	printf "Modifying line:$(awk -F ':' '{print $1}' <<< "$line") of "$IDFILE" : adding the following ids ${varwrite[@]}"
	[[ -n "${ardel[@]}" ]] && ", removing the following ids ${ardel[@]} \n"
elif [[ -z "${varwrite[@]}" && -z "${ardel[@]}" ]]; then
	printf "No pci.ids to add or remove \n"
	exit
fi

read -p "Confirm changes? [y/n]" varuserconf
[[ ! "$vargrub" =~ ^[yY]$ ]] && exit
# we can start by running through the ids to be deleted in ardel, if none are present we will write at the end of the string "vfio-pci.ids=" if present.
for ((i=0; i < "${#arwrite[@]}"; i++)); do
    if [[ -n ${ardel[@]} ]]; then
        for ((target=0; target < "${#ardel[@]}"; target++)); do
        sed -i 's/${ardel[$target]}/${arwrite[$i]}/g' $IDFILE
        unset ${arwrite[$i]}
        #start the next arwrite iteration
        continue
        done
#reaching here if ardel is empty wip
#modify $IDPARAM to change the seaked parameter in $IDFILE
IDPARAM="vfio-pci.ids="
    elif [[ -z ${ardel[@]} ]]; then
        #if there is already a vfio-pci.ids= parameter
        if [[ -n $(grep -Eo "$IDPARAM") ]]; then
                sed -i "/^.*GRUB_CMDLINE_LINUX_DEFAULT|^.*options/ s/$IDPARAM/$IDPARAM${arwrite[$i]},/g"
                unset ${arwrite[$i]}
                continue
        fi
        #if there is neither ids nor vfio-pci.ids=
        if [[ -z $(grep -Eo "$IDPARAM") ]]; then
        end=$(grep -E "^.*options|^.*GRUB_CMDLINE_LINUX_DEFAULT" $IDFILE | grep -oE ".$")
        sed -i -E "/^.*GRUB_CMDLINE_LINUX_DEFAULT|^.*options s/$end/$IDPARAM${arwrite[$i]}$end/g"
        fi
    fi
done



#     if [ -z "$bootloadervfio" ] ; then
#         echo "Appending the ids to /etc/default/grub GRUB_CMDLINE_LINUX_DEFAULT line (requires root privileges)"
#         sed -i "/^GRUB_CMDLINE_LINUX_DEFAULT=/ s/\"$/ vfio-pci.ids=$varwriteids\"/" /etc/default/grub
#         read -p "Run update-grub now? [y/n]:" grubupd
#         [[ "$grubupd" =~ ^[yY]$ ]] && update-grub
#         else
# #Comparing preexisting vfio-pci.ids
#         for ((i=0; i < "${#varwriteids[@]}"; i++)); do
#         # debug echo "i = $i"
#         if [[ ! " ${avfio[@]} " =~ "${varwriteids[$i]}" ]]; then
#                 varwrite+=(${varwriteids[$i]})
#                 unset varwriteids[$i]
#         fi
#         done
#         #modify the grub wip
#         printf "Modifying line:$( grep -Fn 'GRUB_CMDLINE' /etc/default/grub | awk -F ':' '{print $1}') of /etc/default/grub : adding the following ids ${varwrite[@]}"
#         read -p "Confirm changes? [y/n]" vargrub
#         if [[ "$vargrub" =~ ^[yY]$ ]]; then
# #gummiboot support WIP
# elif [[ -f $(which gummiboot 2>/dev/null) ]]; then
#     #determining what folder gummiboot uses
#     [[ -d /boot/loader/ ]] && loader=/boot/loader
#     [[ -d /efi/loader/ ]] && loader=/efi/loader
#     #getting the default .conf file
#     [[ -f $loader/loader.conf ]] && defaultboot=$(awk '{print $2}' $loader/loader.conf)
#     cp $loader/entries/$defaultboot.conf $loader/entries/$defaultboot.back
#     [[ -z $(grep -i options $loader/entries/$defaultboot.conf) ]] && echo "options" >> $loader/entries/$defaultboot.conf
#     if [ -z $(grep -i "[0-9A-Za-z]\{4\}:[0-9A-Za-z]\{4\}") ]; then
#     sed -i "/^options/ s/\$/ vfio-pci.ids=$varwriteids/" $loader/entries/$defaultboot.conf
#     else
#
#     echo "Modified $loader/entries/$defaultboot.conf"
# fi
