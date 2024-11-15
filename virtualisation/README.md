## Installing and setting up virt-manager
this guide follows the instruction method using the gui virt-manager package
> minimal solution with only qemu & libvirt in progress
<details>

<summary>Void Linux Installation</summary>

#### Install the required packages
```
# xbps-install -S virtmanager libvirt qemu edk2-ovmf
```
create symlinks for libvirt deamons in the services directory
```
# ln -s /etc/sv/virtlockd /var/service
# ln -s /etc/sv/virtlogd /var/service
# ln -s /etc/sv/libvirtd /var/service
```
either reboot the system or run `# sv up <deamon>` for every deamon (ie. `sv up virtlockd` , etc.)

</details>

<details>

<summary>Gentoo Linux Installation</summary>

#### Setting up your package.use file
Create a new file in `/etc/portage/package.use/XX-qemu`, eg:
```
vim /etc/portage/package.use/15-qemu
```
```
# qemu
app-emulation/qemu -oss fuse nfs usbredir spice usb

# libvirt
app-emulation/libvirt fuse lvm nbd
>=net-dns/dnsmasq-2.90 script
>=net-libs/gnutls-3.8.7.1-r1 pkcs11 tools

# optional : if you wish to use a GUI manager
# virtmanager
app-emulation/virt-manager gui
>=net-misc/spice-gtk-0.42-r4 usbredir gtk3
```
#### Finally install the packages :
app-emulation/virt-manager is optional and for GUI
```
# emerge -a app-emulation/qemu app-emulation/libvirt sys-firmware/edk2 app-emulation/virt-manager 
```
     
</details>


## Continuing configuration
You also need to add your user account to groups :
```
# usermod -aG input <user>
# usermod -aG libvirt <user> 
```
> Replace <$user> with your user account, ex: usermod -aG input elise

set up vfio gpu drivers is the next step before creating the vm:

## Setting up vfio pci ids with vfio-assisted-config.sh
Use the script (needs root priviledges to edit system configuration files and generate the initramfs)

Done :)

or :
## Manual steps
run the follow command on the host system to display devices with IOMMU groups and their respective pci.ids
```
	shopt -s nullglob
	for d in /sys/kernel/iommu_groups/{0..999}/devices/*; do
		n=${d#*/iommu_groups/*}; n=${n%%/*}
		printf 'IOMMU Group %s ' "$n"
		lspci -nns "${d##*/}"
	done;
```
(you should be able to copy and paste directly in your shell, or put it in a .sh file if you prefer to run it manually)

```
$ bash ./iommu.sh
[...]
IOMMU Group 22 04:00.0 VGA compatible controller [0300]: NVIDIA Corporation GP107 [GeForce GTX 1050 Ti] [10de:1c82] (rev a1)
IOMMU Group 22 04:00.1 Audio device [0403]: NVIDIA Corporation GP107GL High Definition Audio Controller [10de:0fb9] (rev a1)
IOMMU Group 23 ...
[...]
```
> All the devices in the IOMMU group 22 of my target GPU need to be bound to the vfio driver during boot.
>
Take note of the pci.ids at the end of the lines of all devices in the target's IOMMU group, here:
`[10de:1c82]` & `[10de:0fb9]`
## Include those devices into the vfio-pci.ids kernel parameter
edit the `GRUB_CMDLINE_LINUX_DEFAULT=` line in `/etc/default/grub` by adding `vfio-pci.ids=<ID>,<ID2>` for example:
```
GRUB_CMDLINE_LINUX_DEFAULT="vfio-pci.ids=10de:1c82,10de:0fb9 loglevel=4"
```
don't forget to update grub
```
# update-grub
```

## Ensuring the vfio driver is loaded early at boot
modify `/etc/dracut.conf.d/20-vfio.conf` with a text editor:
```
force_drivers+=" vfio_pci vfio vfio_iommu_type1 "
```
regenerate the initramfs using dracut:
```
# dracut -f
```
or run 
```
# xbps-reconfigure linux<x.x>
```
(replace <x.x> with version number ie : 6.6)

## Reboot your device to ensure that the GPU is bound to the VFIO drivers
```
# lspci -k | grep -A 2 'NVIDIA'
```
(alternatively if you know the domain of the device you can run
```
# lspci -s 04:00 -k
```
> replace 'NVIDIA' with 'AMD' or your GPU/PCI device manufacturer.
> 
Expected output :
```
04:00.0 VGA compatible controller: NVIDIA Corporation GP107 [GeForce GTX 1050 Ti] (rev a1)
        Subsystem: PNY Device 11bf
        Kernel driver in use: vfio-pci
--
04:00.1 Audio device: NVIDIA Corporation GP107GL High Definition Audio Controller (rev a1)
        Subsystem: PNY Device 11bf
        Kernel driver in use: vfio-pci
--
```
> note that both devices `04:00.0` and `04:00.1` need to be bound to the VFIO driver, as well as any other device in the same IOMMU group as the target GPU when using iommu.sh

