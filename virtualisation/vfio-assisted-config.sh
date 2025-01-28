#!/bin/bash

# This script aims to automate the configuration needed to use the vfio drivers
# on specific pci devices / iommu group. The sources for third party code have
# been explicited. Some actions require elevated privileges, like setting up
# $DIRDRACUT/99-vfio.conf, regenerating the initramfs, configuring the
# vfio-pci.ids on GRUB, and updating the grub. The script is heavily influenced
# by the use of NVIDIA GPUs, please help make it more manufacturer agnostic.

#             Always read a script you download from the internet.             #

# note: variables with in CAPITAL LETTERS can be modified by the end user depending on
# local configuration and needs


# Checking dracut configuration folders and the status of a vfio.conf file,
# wether lines not starting with the '#' are present in /etc/dracut.conf

FILEDRACUT=/etc/dracut.conf
DIRDRACUT=/etc/dracut.conf.d
if [[ -z $(which systemd 2>/dev/null) ]]; then
	if [[ -z $(grep -o "^[^#]" $FILEDRACUT) && ! -d "$DIRDRACUT" ]]; then
	echo -e "Either the configuration folder $DIRDRACUT doesn't exist and the file\
	 $FILEDRACUT hasn't been initiated, \nor the script wasn't run with the \
	appropriate permissions."
	exit
	fi
fi

# This will be the name of the new dracut configuration file for vfio drivers, feel free to change it
DRACUTCONF="99-vfio.conf"
# As well as added arguments
DRACUTARGS="vfio_pci vfio vfio_iommu_type1"
# some config might need different args (WIP)
#DRACUTARGS="intel args"

# Going to determine which location to use in case both /etc/dracut.conf 
# & /etc/dracut.conf.d are used [WIP]
#if [[ -n $(grep -o "^[^#].*" $FILEDRACUT) && -d $DIRDRACUT ]]; then
#echo "Both the file /etc/dracut.conf and /etc/dracut.conf.d/ directory seem to be used"
#read -p "Please enter the path of the file or folder you wish to use" varwhichconf
#[[ -f "$varwhichconf" ]] && dracutfp="$varwhichconf"
#[[ -d "$varwhichconf" ]] && DIRDRACUT="$varwhichconf"
#fi

dracutfp="$DIRDRACUT/$DRACUTCONF"

if [[ -z "$(grep -ER "(force_drivers)?.*$DRACUTARGS" "$DIRDRACUT")" ]]; then
	if [[ ! -f "$dracutfp" ]]; then
	echo "Adding the following line to $dracutfp:"
	# could run this silently, but I like being explicit
	tee $dracufp <<< "force_drivers+=\" vfio_pci vfio vfio_iommu_type1 \"" #>/dev/null
	read -p "Regenerate initramfs now? [y/N]:" vargen
	[[ "$vargen" =~ ^[yY]$ ]] && dracut -f
	else
	read -p "File "$dracutfp" already exists, overwrite? [y/N]" varfileexists
	[[ $varfileexists =~ ^[yY]$ ]] && tee $dracufp <<< "force_drivers+=\"vfio_pci vfio vfio_iommu_type1 \""
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
else
	displaygroups=$(iommuscript | grep -i "$vargpumkr")
	if [[ -n "$displaygroups" ]]; then echo "$displaygroups"
	else echo -e "No match found, displaying all IOMMU groups:\n" || iommuscript
	fi
fi
echo "Please enter the main IOMMU group which you would like to passthrough:"
echo "You can passthrough multiple IOMMU groups with a comma, eg: 18,24,32"
read -p "IOMMU GROUP "  vargroup

# Edit spaces / commas
vargroup=$(sed 's/,/ /g' <<< "$vargroup")
# [WIP] more chekcs to verify that the syntax of user input is correct
for i in $vargroup; do newgroups+=($i); done

# creating array of pci ids
vfioids="[[:alnum:]]\{4\}:[[:alnum:]]\{4\}"

arids=()
for i in "${newgroups[@]}"
do id=$(iommuscript | grep "IOMMU Group $i" | grep -o "$vfioids")
arids+=($id)
done
	
echo -e "PCI IDs configuration: ${arids[*]}"
# modify the array to fit the 'vfio-pci.ids=' syntax
varwriteids=$(sed "s/ /,/g" <<< ${arids[*]})
# check which bootloader may be installed
if [[ -f $(which grub 2>/dev/null) ]]; then
	BOOTFILE=/etc/default/grub
	cp -p $BOOTFILE $BOOTFILE.backup
# also check for gummiboot / systemd-boot (same conf)
elif [[ -f $(which gummiboot 2>/dev/null) || -f $(which bootctl 2>/dev/null) ]]; then
	LOADER=loader.conf
	[[ -d /efi ]] && CONFFILE=$(find /efi -name $LOADER 2>/dev/null)
	[[ -d /boot && -z "$CONFFILE" ]] && CONFFILE=$(find /boot -name $LOADER 2>/dev/null)

# CONFFILE override (eg: /boot )
# CONFFILE=/path/to/file.conf

	[[ -z "$CONFFILE" ]] && echo "Could not find the proper boot folder; exiting" && exit

	IDPATH="$(sed 's/\/*.conf//g' <<< $CONFFILE)/entries/"
	IDFILE=$(grep default "$CONFFILE" | awk '{print $2}')
	if [[ -n "$IDFILE" ]]; then 
		IDFILE=$IDFILE.conf
	else
		[[ -z "$(ls $IDPATH/*.conf 2>/dev/null)" ]] && echo "No boot configuration found, please review systemd-boot / gummiboot configuration"
		[[ ! 1 == "$(ls -1 $IDPATH*.conf | wc -l)" ]] && IDFILE="$(ls $IDPATH*.conf)"
	fi
	cp -p "$IDPATH$IDFILE" "$(sed 's/\/$//g' <<< $IDPATH)/$IDFILE.backup"
	BOOTFILE="$IDPATH$IDFILE"
	#BOOTFILE="/efi/loader/entries/6.6.58-gentoo-dist.conf"
	[[ -z $(grep -o "options" "$BOOTFILE") ]] && printf "options" >> "$BOOTFILE"
	# Check with the user that the right boot file is used
	read -p "Boot configuration detected = $BOOTFILE [y/N]:" varboot
	[[ ! "$varboot" =~ ^[yY]$ ]] && exit
fi

# you can override the $IDFILE variable here
#IDFILE=/path/to/file
aprevfio=()
for i in $(grep -o "$vfioids" $BOOTFILE); do
	aprevfio+=($i)
done
ardel=()
arwrite=()
# Comparing those ids with iommuscript's output
for ((i=0; i < "${#aprevfio[@]}"; i++)); do
	[[ -n "$(grep "${aprevfio[$i]}" <<< "${ardel[*]}")" ]] && break
	if [[ ! " ${arids[@]} " =~ "${aprevfio[$i]}" ]];
	then ardel+=(${aprevfio[$i]})
	fi
done

for ((i=0; i < "${#arids[@]}"; i++)); do
	if [[ ! " ${aprevfio[@]} " =~ "${arids[$i]}" ]]
	then arwrite+=(${arids[$i]})
	fi
done

# Writing changes to files
# The $line variable is only set for cosmetic reasons
line=$(grep -En "GRUB_CMDLINE_LINUX_DEFAULT|options" $BOOTFILE | head -n 1)

if [[ -n "${arwrite[@]}" ]]; then
	printf "Modifying line:$(awk -F ':' '{print $1}' <<< "$line") \
of "$BOOTFILE" \nAdding ids : ${arwrite[*]}\n"
	[[ -n "${ardel[@]}" ]] && printf "Removing ids : ${ardel[*]} \n"
elif [[ -z "$arwrite[@]}" && -z "${ardel[@]}" ]]; then
	echo "No pci.ids to add or remove \n"
	exit
fi

# we can start by running through the ids to be deleted in ardel,
# if none are present we will write at the end of the string "vfio-pci.ids="

# nuclear options : sed -i "/^options/ s/($vfioids[, ])*//g"\
# /efi/loader/entries/6.6.58-gentoo-dist.conf
# debug
#echo "ardel ${ardel[@]}"
#echo "arwrite ${arwrite[@]}"
#

BOOTPATTERN="^.*GRUB_CMDLINE_LINUX_DEFAULT|^.*options"
IDPARAM="vfio-pci.ids="

for ((i=0; i < "${#arwrite[@]}"; i++)); do
[[ -n "$(grep "${arwrite[$i]}" $BOOTFILE)" ]] && echo "${arwrite[$i]} already in $BOOTFILE" && break
if [[ -n "$(grep "$vfioids" <<< "${ardel[@]}")" ]]; then
	sed -i "s/${ardel[$i]}/${arwrite[$i]}/g" $BOOTFILE
	del="${ardel[$i]}"
	ardel=("${ardel[@]/$del}")
else
	if [[ -n $(grep -o "$IDPARAM" $BOOTFILE) ]]; then
		sed -i -E "/$BOOTPATTERN/ s/$IDPARAM/$IDPARAM${arwrite[$i]},/g" $BOOTFILE
		continue
	else
	# GRUB has a trailing ending quote character on its configuration line
	# checking for it ensures that this script is compatible on GRUB and GRUBless
	# systems
	end=$(grep "$BOOTPATTERN" $BOOTFILE | grep -oE "\"$")
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
	if [[ -n "$(grep -E "$BOOTPATTERN" $BOOTFILE | grep -Eo ",{1,}$")" ]]; then
	#removing trailing commas but keeping
	sed -i -E "/$vfioids/ s/,{1,} / /g;s/(,{1,}$)//g" $BOOTFILE
	fi
	done

# Final user confirmation [WIP]
echo "The boot configuration has been modyfied:"
	diff $BOOTFILE $BOOTFILE.backup
	read -p "Would you like to keep the changes? [y/N] \n" varusercheck
	if [[ ! "$varusercheck" =~ ^[yY]$ ]]; then
	rm $BOOTFILE
	cp -p $BOOTFILE.backup $BOOTFILE
	fi
