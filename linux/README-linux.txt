K114s repair, bundle r2 - files for the Linux side (this folder is on the ESP: /boot/efi/k114s-repair/r2)

After an "Omarchy K114s repair" boot entry works, run once in a terminal:
    sudo bash /boot/efi/k114s-repair/r2/linux-persist.sh
Undo:
    sudo bash /boot/efi/k114s-repair/r2/linux-persist.sh --undo

Until you have run it, do not update packages (the stock update hook can replace the K114s boot
file and Linux would stop starting; macOS would still start).

After you have run it:
  - Update > Omarchy (omarchy update) is expected to work. Its last step prints a warning that this
    Mac's owner manages the boot chain; that is this repair, and the update finishes.
  - To see what an update would change before running it:
        sudo /usr/local/lib/omarchy-k114s/k114s-edge-check
  - The Omarchy channel switch (Update > Channel) stops with "K114s hold guard: stopped" and changes
    nothing. The switch replaces Omarchy itself with Edge's build, and that combination has not
    been run on a K114s yet. Everything else already follows the Edge repositories.
  - If an update stops with "K114s hold guard: stopped", nothing was changed. Run
        sudo /usr/local/lib/omarchy-k114s/apply-holds
    and update again.
