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
	read -p "Regenerate initramfs now? [y/n]:" vargen; [[ "y" == "$vargen" ]] && dracut -f && clear;
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
	echo "No manufacturer entered, displaying all IOMMU groups:" && sleep 2
	iommuscript
elif [[ -n "$vargpumkr" ]]; then
	displaygroups=$(iommuscript | grep -i "$vargpumkr")
	[[ -n "$displaygroups" ]] && echo "$displaygroups" || echo -e "No match found, displaying all IOMMU groups:\n" || iommuscript
fi
echo "Please enter the IOMMU group which you would like to passthrough:"
read -p "IOMMU GROUP "  vargroup

##creating array of pci ids
arids=(); vfioids="[0-9A-Za-z]\{4\}:[0-9A-Za-z]\{4\}"
	for i in $(iommuscript | grep "IOMMU Group $vargroup" | grep -o "$vfioids"); do arids+=($i); done

	echo -e "PCI IDs configuration: ${arids[*]}"
	read -p "Continue with these settings? [y/N]:" vardoconfig
	[[ ! "$vardoconfig" =~ ^[yY]$ ]] && echo "exiting script" && exit
	#modify the array to fit the kernel's command line syntax
	varwriteids=$(echo ${arids[*]} | sed "s/ /,/g")
	#check wether /etc/default/grub already has pci.ids entries (todo: make sure to read from the "GRUB_CMDLINE_LINUX_DEFAULT=" line)
	#check which bootloader may be installed
	if [[ -f $(which grub 2>/dev/null) ]]; then
		IDFILE=/etc/default/grub
		cp $IDDIR/$BOOT /etc/default/backup.grub
		#DEBUG TESTING GRUB
	elif [[ -f $(which gummiboot 2>/dev/null) ]]; then
		CONFFILE=/boot/loader/loader.conf
		IDFILE=/boot/loader/entries/$(awk '{print $2}' $CONFFILE).conf
		cp $IDFILE /boot/loader/entries/backup
		[[ -z $(grep -o "options" $IDFILE) ]] && printf "options" >> $IDFILE
	fi

# If you have a different bootloader or different configuration, you can override the $IDFILE variable here by uncommenting the following line and including the URI to the file where your pci.ids are written
#IDFILE=/path/to/file

for i in $(grep -o "$vfioids" $IDFILE); do
	avfio+=($i)
done

# Comparing those ids with iommuscript's output
# ardel is an array with ids in the bootloader's config file which do not match the output of this script;
# checking against avfio
for ((i=0; i < "${#avfio[@]}"; i++)); do
	if [[ ! " ${arids[@]} " =~ "${avfio[$i]}" ]];
	then ardel+=(${avfio[$i]})
		#removing that id from avfio so that only ids matching with arids remain in it
	fi
done
# Running that comparison again this time checking whether any entry in arids is already present in the bootloader's config file, if it isn't, it needs to be written and is added to the array arwrite
for ((i=0; i < "${#arids[@]}"; i++)); do
	if [[ ! " ${avfio[@]} " =~ "${arids[$i]}" ]]
	then arwrite+=(${arids[$i]})
	fi
done

## Writing changes to files
# The $line variable is only set for cosmetic reasons
line=$(grep -En "GRUB_CMDLINE_LINUX_DEFAULT|options" $IDFILE | head -n 1)
echo "$line"

if [[ -n "${arwrite[@]}" ]]; then
	printf "Modifying line:$(awk -F ':' '{print $1}' <<< "$line") of "$IDFILE" \nAdding ids : ${arwrite[*]}\n"
	[[ -n "${ardel[@]}" ]] && printf "Removing ids : ${ardel[*]} \n"
elif [[ -z "$arwrite[@]}" && -z "${ardel[@]}" ]]; then
	echo "No pci.ids to add or remove \n"
	exit
fi

read -p "Confirm changes? [y/n]" varuserconf
[[ ! "$varuserconf" =~ ^[yY]$ ]] && exit
# we can start by running through the ids to be deleted in ardel, if none are present we will write at the end of the string "vfio-pci.ids=" if present.
echo "arwrite ${arwrite[@]}"; echo "total "${#arwrite[@]}""
for ((i=0; i < "${#arwrite[@]}"; i++)); do
	if [[ -n "${ardel[@]}" ]]; then
		sed -i "s/${ardel[$i]}/${arwrite[$i]}/g" $IDFILE
	elif [[ -z "${ardel[@]}" ]]; then
		BOOTGLOB="^.*GRUB_CMDLINE_LINUX_DEFAULT|^.*options"
		IDPARAM="vfio-pci.ids="
		if [[ -n $(grep -o "$IDPARAM" $IDFILE) ]]; then
			sed -i "/$BOOTGLOB/ s/$IDPARAM/$IDPARAM${arwrite[$i]},/g" $IDFILE
			continue
		fi
		if [[ -z $(grep -o "$IDPARAM" $IDFILE) ]]; then
		end=$(grep -E "$BOOTGLOB" $IDFILE | grep -oE "\"$")
		[[ -z "$end" ]] && sed -i -E "/$BOOTGLOB/ s/$/$IDPARAM${varwriteids[*]}/g" $IDFILE
		[[ -n "$end" ]] && sed -i -E "/$BOOTGLOB/ s/$end/$IDPARAM${varwriteids[*]}$end/g" $IDFILE
		break
		fi
	fi
	#checking if there is any additional values to be deleted through ardel
done
