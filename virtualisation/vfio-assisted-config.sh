#!/bin/bash

# This script aims to automate the configuration needed to use the vfio drivers
# on specific pci devices / iommu group. The sources for third party code have
# been explicited. Some actions require elevated privileges, like setting up
# $DIRDRACUT/20-vfio.conf, regenerating the initramfs, configuring the
# vfio-pci.ids on GRUB, and updating the grub. The script is heavily influenced
# by the use of NVIDIA GPUs, please help make it more manufacturer agnostic.

#             Always read a script you download from the internet.             #

# note: variables with in CAPITAL LETTERS can be modified by the end user depending on
# local configuration and needs


# Checking dracut configuration folders and the status of a vfio.conf file
DIRDRACUT=/etc/dracut.conf.d
if [[ ! -d "$DIRDRACUT" ]]; then
	echo "Script obsolete review dracut.conf.d"
	exit
fi

DRACUTARGS="vfio_pci vfio vfio_iommu_type1"
DRACUTCONF="99-vfio.conf"
dracutvfio="$(grep -ER "(force_drivers)?.*($(sed "s/ /|/g" <<< $DRACUTARGS))" $DIRDRACUT)"
dracutfp="$DIRDRACUT/$DRACUTCONF"

if [[ -z "$dracutvfio" ]]; then
	if [[ -f "$dracutfp" ]]; then
		read -p "File "$dracutfp" already exists, overwrite? [y/N]" varfileexists
		[[ $varfileexists =~ ^[yY]$ ]] && tee "$dracufp" <<< "force_drivers+=\" vfio_pci vfio vfio_iommu_type1 \""
	else
		echo "Adding the following line to $dracutfp:"
		# could run this silently, but I like being explicit
		#tee "$dracufp" <<< "force_drivers+=\" vfio_pci vfio vfio_iommu_type1 \"" >/dev/null
		tee "$dracufp" <<< "force_drivers+=\" vfio_pci vfio vfio_iommu_type1 \""
		read -p "Regenerate initramfs now? [y/n]:" vargen
		[[ "$vargen" =~ ^[yY]$ ]] && dracut -f
	fi
fi

# setting up the iommu script function
# script from : https://wiki.archlinux.org/title/PCI_passthrough_via_OVMF#Enabling_IOMMU
function iommuscript {
	# change the 999 if needed
	shopt -s nullglob
	for d in /sys/kernel/iommu_groups/{0..999}/devices/*; do
		n=${d#*/iommu_groups/*}; n=${n%%/*}
		printf 'IOMMU Group %s ' "$n"
		lspci -nns "${d##*/}"
	done;
}

# get pci.ids values from the IOMMU group of target gpu pci device
echo "Please enter your PCI device manufacturer [Press enter for unknown]"
read vargpumkr
if [ -z "$vargpumkr" ]; then
	echo "No manufacturer entered, displaying all IOMMU groups:" && sleep 2
	iommuscript
elif [[ -n "$vargpumkr" ]]; then
	displaygroups=$(iommuscript | grep -i "$vargpumkr")
	[[ -n "$displaygroups" ]] && echo "$displaygroups" || echo -e "No match found, displaying all IOMMU groups:\n" || iommuscript
fi
echo "Please enter the main IOMMU group which you would like to passthrough:"
echo "You can passthrough multiple IOMMU groups with a comma, eg: 18,24,32"
read -p "IOMMU GROUP "  vargroup

# Check for spaces / commas
argroups=()

if [ -n $(grep -E "[ ,]" <<< "$vargroup") ]; then
	newgroups=$(sed 's/,/ /g' <<< $vargroup)
	for i in $newgroups; do argroups+=($i); done
fi

# creating array of pci ids
arids=(); vfioids="[[:alnum:]]\{4\}:[[:alnum:]]\{4\}"
	
	for i in "${argroups[@]}"
		do id=$(iommuscript | grep "IOMMU Group $i" | grep -o "$vfioids")
		arids+=($id)
	done
	
	echo -e "PCI IDs configuration: ${arids[*]}"
	# modify the array to fit the kernel's command line syntax
	varwriteids=$(sed "s/ /,/g" <<< ${arids[*]})
	# check which bootloader may be installed
	# todo: use install instead of cp (may be ok with cp -p ?)
	if [[ -f $(which grub 2>/dev/null) ]]; then
		BOOTFILE=/etc/default/grub
		cp -p $BOOTFILE /etc/default/backup.grub
	# also check for gummiboot / systemd-boot (same conf)
	elif [[ -f $(which gummiboot 2>/dev/null) || -f $(which bootctl 2>/dev/null) ]]; then
		LOADER=loader.conf
		[[ -d /efi ]] && CONFFILE=$(find /efi -name $LOADER 2>/dev/null)
		[[ -d /boot && -z "$CONFFILE" ]] && CONFFILE=$(find /boot -name $LOADER 2>/dev/null)
		
		# CONFFILE override (eg: /boot )
		#CONFFILE=/path

		[[ -z "$CONFFILE" ]] && echo "Could not find the proper boot folder; exiting" && exit

		IDPATH="$(sed 's/\/[A-Za-z0-9]*.conf//g' <<< $CONFFILE)/entries/"
		IDFILE=$(grep default "$CONFFILE" | awk '{print $2}').conf
		cp -p "$IDPATH$IDFILE" "$(sed 's/\/$//g' <<< $IDPATH)/backup.$IDFILE"
		BOOTFILE="$IDPATH$IDFILE"
		[[ -z $(grep -o "options" "$BOOTFILE") ]] && printf "options" >> "$BOOTFILE"
		# Check with the user that the right boot file is used
		read -p "Boot configuration detected = $BOOTFILE [y/N]:" varboot
		[[ ! "$varboot" =~ ^[yY]$ ]] && exit
fi

# you can override the $IDFILE variable here
#IDFILE=/path/to/file

for i in $(grep -o "$vfioids" $BOOTFILE); do
	avfio+=($i)
done

# Comparing those ids with iommuscript's output
for ((i=0; i < "${#avfio[@]}"; i++)); do
	if [[ ! " ${arids[@]} " =~ "${avfio[$i]}" ]];
	then ardel+=(${avfio[$i]})
	fi
done

for ((i=0; i < "${#arids[@]}"; i++)); do
	if [[ ! " ${avfio[@]} " =~ "${arids[$i]}" ]]
	then arwrite+=(${arids[$i]})
	fi
done

# Writing changes to files
# The $line variable is only set for cosmetic reasons
line=$(grep -En "GRUB_CMDLINE_LINUX_DEFAULT|options" $BOOTFILE | head -n 1)

if [[ -n "${arwrite[@]}" ]]; then
	printf "Modifying line:$(awk -F ':' '{print $1}' <<< "$line") of "$BOOTFILE" \nAdding ids : ${arwrite[*]}\n"
	[[ -n "${ardel[@]}" ]] && printf "Removing ids : ${ardel[*]} \n"
elif [[ -z "$arwrite[@]}" && -z "${ardel[@]}" ]]; then
	echo "No pci.ids to add or remove \n"
	exit
fi

# we can start by running through the ids to be deleted in ardel,
# if none are present we will write at the end of the string "vfio-pci.ids="

# nuclear options : sed -i -E "/^options/ s/([0-9A-Za-z]{4}:[0-9A-Za-z]{4}[, ])*//g" /efi/loader/entries/6.6.58-gentoo-dist.conf

# debug
#echo "ardel ${ardel[@]}"
#echo "arwrite ${arwrite[@]}"
#

for ((i=0; i < "${#arwrite[@]}"; i++)); do
	if [[ -n "${ardel[@]}" ]]; then
		sed -i "s/${ardel[$i]}/${arwrite[$i]}/g" $BOOTFILE
		del="${ardel[$i]}"
		ardel=("${ardel[@]/$del}")
	elif [[ -z "${ardel[@]}" ]]; then
		BOOTPATTERN="^.*GRUB_CMDLINE_LINUX_DEFAULT|^.*options"
		IDPARAM="vfio-pci.ids="
		if [[ -n $(grep -o "$IDPARAM" $BOOTFILE) ]]; then
			sed -i -E "/$BOOTPATTERN/ s/$IDPARAM/$IDPARAM${arwrite[$i]},/g" $BOOTFILE
			continue
		elif [[ -z $(grep -o "$IDPARAM" $BOOTFILE) ]]; then
		end=$(grep -E "$BOOTPATTERN" $BOOTFILE | grep -oE "\"$")
		[[ -z "$end" ]] && sed -i -E "/$BOOTPATTERN/ s/$/ $IDPARAM${varwriteids[*]}/g" $BOOTFILE
		[[ -n "$end" ]] && sed -i -E "/$BOOTPATTERN/ s/$end/ $IDPARAM${varwriteids[*]}$end/g" $BOOTFILE
		break
		fi
	fi
done

# Checking if there are any more ids to delete
# TODO finish this monster
	for ((i=0; i < ${#ardel[@]}; i++)); do
	[[ -n ${ardel[$i]} ]] && sed -i "s/${ardel[$i]}//g" $BOOTFILE
	#checking for any number of commas "," trailing the end line
	[[ -n $(grep $BOOTPATTERN <<< $BOOTFILE | grep -o "\{2,\}") ]] && sed -i -e "/[[:alnum:]]\{4\}:[[:alnum:]]\{4\} s/\{2,\}[ \$]//g" $BOOTFILE
	done

# Final user confirmation
#echo "The boot configuration has been modyfied:"
#echo "$(diff $BOOTFILE $IDDIR/
