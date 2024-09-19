## installing and setting up virt-manager
this guide follows the instruction method using the gui virt-manager package
> minimal solution with only qemu & libvirt in progress
```
# xbps-install -S virtmanager libvirt qemu
```
create symlinks for libvirt deamons in the services directory
```
# ln -s /etc/sv/virtlockd /var/service
# ln -s /etc/sv/virtlogd /var/service
# ln -s /etc/sv/libvirtd /var/service
```
either reboot the system or run `# sv up <deamon>` for every deamon (ie. virtlockd)

setting up vfio gpu drivers is the next step before creating the vm

## setting up vfio pci ids with the script in ./
### Use the script vfio-assisted-config.sh

## manual steps
run `./scripts/iommu.sh` on the host system to display devices with IOMMU groups and their respective pci.ids
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
## include those devices into the vfio-pci.ids kernel parameter
edit the `GRUB_CMDLINE_LINUX_DEFAULT=` line in `/etc/default/grub` by adding `vfio-pci.ids=<ID>,<ID2>` for example:
```
GRUB_CMDLINE_LINUX_DEFAULT="vfio-pci.ids=10de:1c82,10de:0fb9 loglevel=4"
```
don't forget to update grub
```
# update-grub
```

## ensuring the vfio driver is loaded early at boot
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

## reboot your device to ensure that the GPU is bound to the VFIO drivers
```
# lspci -k | grep -A 2 'NVIDIA'
```
> replace 'NVIDIA' with 'AMD' or your GPU manufacturer.
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
This allows you to fully use the normally passedthrough GPU on the host OS
>note that these instructions can be reversed in order to boot normally without the vfio drivers and only passthrough the GPU when booting a custom grub entry
>
`[work in progress]`
