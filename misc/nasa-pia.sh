#!/bin/bash

# Purpose : when downloading images from nasa's library files can be named PIA or their filename
# this script will run through all the images and compare classic filanames with PIA*
# if the sha checksum is equal then it will delete the PIA file
# it then runs a comparison whether the filename has a trailing [::space::] before its extension
# if it's found it will remove it

for i in ./*.tif; do
	    root=$(sha1sum "$i" | awk -F ' ' '{print $1}')
	if [ -n "$(ls ./PIA*.tif 2>/dev/null)" ]; then
		for a in ./PIA*.tif; do
	    	[[ "$root" == "$(sha1sum "$a" | awk '{print $1}')" ]] && rm ./"$a"
		done
	fi
# check for trailing [::space::] in filename	
newname=$(echo "$i" | sed 's/[[:space:]]\+\.tif$/.tif/')
if [ "$i" != "$newname" ]; then
  mv "$i" "$newname"
fi
