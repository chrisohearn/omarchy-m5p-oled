K114s repair, bundle r2c - files for the Linux side (this folder is on the ESP: /boot/efi/k114s-repair/r2c)

Not needed for a first test of the trackpad and Wi-Fi.

Once the repair entry works, it makes the repair survive a later boot-image rebuild:
    sudo bash /boot/efi/k114s-repair/r2c/linux-persist.sh
Undo:
    sudo bash /boot/efi/k114s-repair/r2c/linux-persist.sh --undo

If the repair entry boots but has no Wi-Fi (no wl* interface), run the line above and restart:
it also installs the Wi-Fi firmware on the Linux disk.

Do not update packages yet, before or after running it. The EFI partition has about 20 MB free
with this repair on it, and an update can rebuild an 80 MB boot image there. After running it,
a guard stops package changes ("K114s space guard: stopped") until the partition has 100 MB free.
The Omarchy channel switch (Update > Channel) is stopped too ("K114s hold guard: stopped").
