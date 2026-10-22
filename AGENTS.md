Don't install nix
Use linuxvm identity to ssh in the VM containing the FVP
Use /Volumes/Ext/VM_SharedFolder to share files with the VM. It contains bash script to launch the FVP. They must be run from inside the VM.
The shared folder can be used to copy the elf before running it with FVP.
If you need to clone git repo, don't clone history. Use depth one to avoid downloading too many things.
FVP must not display any UI (we don't have one in the VM). So UI should be disabled in FVP config options.

