# banepanel-scripts
Useful scripts for GNU/Linux systems.

`
[Y] supported 
`

`
[N] unsupported 
`

## Virtualisation
- VFIO Assisted Config :
    Automatically add the required PCI IDS to your bootloader and initramfs configuration, can also edit other PCI IDS in the configuration files and remove them if necessary. You can read more about what the script is doing at `/scripts/virtualisation/README.md`
    
    Bootloader : `grub [Y] | gummiboot / systemd-boot [Y] | efistub [N]`

    initramfs : `dracut [Y] | mkinitcpio [N]`
