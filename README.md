# noresm2_mpc
Scripts and modified F90 files for adjusting mixed-phase cloud behavior in NorESM2

Initial Organization (071119):
/Scripts:
This folder includes the bash and python scripts that read in the desired parameter sets, move the SourceMod files to the new case, and modify those files to adjust the model behavior.

/SourceMods:
This folder includes the modified F90 files that will be modified and plugged into the model.

Operation:
Ideally, anyone wishing to use this repository can clone it into a remote HPC, modify the paths and model parameters in the bash script in /Scripts, and then run it!

This branch has micro_mg2_0.F90 modified to not limit ice number concentration above -38C, where we were working with mixed-phase clouds.
