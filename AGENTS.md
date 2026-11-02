Don't install nix

On a mac, to launch FVP:

* Use linuxvm identity to ssh in the VM containing the FVP
* Use /Volumes/Ext/VM_SharedFolder to share files with the VM. It contains bash script to launch the FVP. They must be run from inside the VM. The shared folder can be used to copy the elf before running it with FVP.

If you need to clone git repo, don't clone history. Use depth one to avoid downloading too many things.

FVP must not display any UI (we don't have one in the VM). So UI should be disabled in FVP config options.

Original lean c/cpp runtime must not be modified directly to make it easier to update. Changes should be recorded as a patch to apply to the original sources.

cmake is only used for the lean part. The remaining part of the build is handled as usual with csolution, cproject and CMSIS packs and components.
cmake should be kept to the minimum required to build the lean part.