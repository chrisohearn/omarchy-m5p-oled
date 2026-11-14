K114s repair r1 - files for the Linux side (this folder is on the ESP: /boot/efi/k114s-repair/r1)

After an "Omarchy K114s repair" boot entry works, run once in a terminal:
    sudo bash /boot/efi/k114s-repair/r1/linux-persist.sh
Undo:
    sudo bash /boot/efi/k114s-repair/r1/linux-persist.sh --undo
Until you have run it, do not update packages or change the Omarchy channel (the stock update
hook would replace the K114s boot file and Linux would stop starting; macOS would still start).
