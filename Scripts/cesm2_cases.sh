#!/bin/bash
# ^specify bash as interpreter

# Copied from slf_and_inp.sh by Jonah Shaw 2020/04/25 (corona time fuckers).
# Aiming for the same functionality, but with CESM2.1.0. Will merge if possible without too much complexity.
# Useful documentation on where to make model adjustments:
#   http://www.cesm.ucar.edu/events/tutorials/2018/files/Practical4-intro-hannay.pdf

############
# FUNCTIONS
############

# Search and replace function
function ponyfyer() {
    local search=$1 ;
    local replace=$2 ;
    local loc=$3 ;
    # Note the double quotes
    sed -i "s/${search}/${replace}/g" ${loc} ;
}

################
# SET INPUT ARGS
################

args=("$@")
CASENAME=${args[0]}  # uniquecasename, maybe add a timestamp in the python script
wbf=${args[1]}          # wbf multiplier
inp=${args[2]}          # inp multiplier

#echo ${args[0]} ${args[1]} ${args[2]}

#####################
# SET CASE PARAMETERS
#####################

models=("noresm-dev" "cesm" "noresm-dev-10072019")
compsets=("NF2000climo" "N1850OCBDRDDMS" "F2000climo")
resolutions=("f19_tn14" "f10_f10_mg37" "f19_g16" "f19_f19_mg17")
machines=('fram')
projects=('nn9600k' 'nn9252k')
start=('2000-01-01' '2009-03-01') # start date
nudge=('ERA_f19_g16' 'ERA_f19_tn14') # repository where data for nudging is stored

########################
# OPTIONAL MODIFICATIONS
########################

nudge_winds=true
# remove_entrained_ice=false
record_mar_input=false
run_type=devel # fouryear, devel, paramtest
run_period=sat_comp # standard, sat_comp

## Build the case

# Where ./create_case is called from: (do I need a tilde here for simplicity?)
ModelRoot=/cluster/home/jonahks/p/jonahks/models/${models[1]}/cime/scripts # selecting cesm here

# Where the case is setup, and user_nl files are stored
CASEROOT=/cluster/home/jonahks/p/jonahks/cases

# Where FORTRAN files contains microphysics modifications are stored
#ModSource=/cluster/home/jonahks/git_repos/noresm2_mpc/SourceMods
ModSource=/cluster/home/jonahks/git_repos/mpcSourceMods

# Set indices to select from arrays here
COMPSET=${compsets[2]}
RES=${resolutions[3]}
MACH=${machines[0]}
PROJECT=${projects[0]}
MISC=--run-unsupported

if [ $run_period = sat_comp ] ; then
    startdate=${start[1]}
    nudgedir=${nudge[1]}
else
    startdate=${start[0]}
    nudgedir=${nudge[0]}
fi

echo ${CASEROOT}/${CASENAME} ${COMPSET} ${RES} ${MACH} ${PROJECT} $MISC

#############
# Main Script
#############

cd ${ModelRoot} # Move to appropriate directory

# Create env_*.xml files
./create_newcase --case ${CASEROOT}/${CASENAME} \
                 --compset ${COMPSET} \
                 --res ${RES} \
                 --mach ${MACH} \
                 --project ${PROJECT} \
                 $MISC

cd ${CASEROOT}/${CASENAME} # Move to the case's dir

# Set run time and restart variables within env_run.xml
if [ $run_type = devel ] ; then
    # ./xmlchange STOP_OPTION='nmonth',STOP_N='1' --file env_run.xml # standard is 5 days
    ./xmlchange JOB_WALLCLOCK_TIME=00:29:59 --file env_batch.xml
    ./xmlchange NTASKS=-4,NTASKS_ESP=1 --file env_mach_pes.xml
    # shitty hack to allow devel queueing:
    sed -i 's/<arg flag="-p" name="$JOB_QUEUE"/<arg flag="--qos" name="$JOB_QUEUE"/' env_batch.xml
    ./xmlchange JOB_QUEUE='devel' --file env_batch.xml
elif [ $run_type = fouryear ] ; then 
    ./xmlchange STOP_OPTION='nmonth',STOP_N='51' --file env_run.xml # fouryear is a misnomer, using 3m adjustment period
    ./xmlchange JOB_WALLCLOCK_TIME=11:59:59 --file env_batch.xml --subgroup case.run
    ./xmlchange NTASKS=-16,NTASKS_ESP=1 --file env_mach_pes.xml # arbitrary
    ./xmlchange --append CAM_CONFIG_OPTS='-cosp' --file env_build.xml
elif [ $run_type = paramtest ] ; then
    ./xmlchange STOP_OPTION='nmonth',STOP_N='15' --file env_run.xml
    ./xmlchange JOB_WALLCLOCK_TIME=11:59:59 --file env_batch.xml --subgroup case.run
    ./xmlchange NTASKS=-4,NTASKS_ESP=1 --file env_mach_pes.xml # arbitrary
else
    ./xmlchange STOP_OPTION='nmonth',STOP_N='15' --file env_run.xml
    ./xmlchange JOB_WALLCLOCK_TIME=11:59:59 --file env_batch.xml --subgroup case.run
    ./xmlchange NTASKS=-4,NTASKS_ESP=1 --file env_mach_pes.xml # arbitrary
fi

./xmlchange RUN_STARTDATE=$startdate --file env_run.xml

#./xmlchange --file=env_run.xml RESUBMIT=3
# ./xmlchange --file=env_run.xml REST_OPTION=nyears
#./xmlchange --file=env_run.xml REST_N=5

exit 1

# OPTIONAL: Remove entrainment of ice above -35C.
if [ $remove_entrained_ice = true ] ; then
    echo "Adding SourceMod to remove ice entrainment"
    cp ${ModSource}/clubb_intr.F90 /${CASEROOT}/${CASENAME}/SourceMods/src.cam
fi

# OPTIONAL: Nudge winds (pt. 1)
if [ $nudge_winds = true ] ; then
    echo "Making modifications to nudge uv winds. Make sure pt. 2 files are correct."
    ./xmlchange --append CAM_CONFIG_OPTS='--offline_dyn' --file env_build.xml
    ./xmlchange CALENDAR='GREGORIAN' --file env_build.xml 
fi

# Sets up case, creating user_nl_* files.
# namelists can be modified here, or after ./case.build
./case.setup

# SourceMods are made here.

# Move modified WBF process into SourceMods dir:
cp ${ModSource}/micro_mg_cam.F90 /${CASEROOT}/${CASENAME}/SourceMods/src.cam
cp ${ModSource}/micro_mg2_0.F90 /${CASEROOT}/${CASENAME}/SourceMods/src.cam

# Move modified INP nucleation process into SourceMods dir:
cp ${ModSource}/hetfrz_classnuc_oslo.F90 /${CASEROOT}/${CASENAME}/SourceMods/src.cam

# Addings SLF isotherms coordinate needed for micro_mg mods
cp ${ModSource}/cospsimulator_intr.F90 /${CASEROOT}/${CASENAME}/SourceMods/src.cam

# Now use ponyfyer to set the values within the sourcemod files. Ex:
mg2_path=/${CASEROOT}/${CASENAME}/SourceMods/src.cam/micro_mg2_0.F90
inp_path=/${CASEROOT}/${CASENAME}/SourceMods/src.cam/hetfrz_classnuc_oslo.F90

ponyfyer 'wbf_tag = 1.' "wbf_tag = ${wbf}" ${mg2_path}  # wbf modifier
ponyfyer 'inp_tag = 1.' "inp_tag = ${inp}" ${inp_path} # aerosol conc. modifier


#################
# user_nl changes
#################

# CAM adjustments, I don't entirely understand the syntax here, but all the formatting after the first line is totally preserved:

# Modify user_nl files appropriately here to choose output
# list variables to add to first history file here
cat <<TXT2 >> user_nl_cam
fincl1 = 'BERGO', 'BERGSO', 'MNUCCTO', 'MNUCCRO', 'MNUCCCO', 'MNUCCDOhet', 'MNUCCDO'
         'DSTFREZIMM', 'DSTFREZCNT', 'DSTFREZDEP', 'BCFREZIMM', 'BCFREZCNT', 'BCFREZDEP',
         'NUMICE10s', 'NUMICE10sDST', 'NUMICE10sBC',
         'dc_num', 'dst1_num', 'dst3_num', 'bc_c1_num', 'dst_c1_num', 'dst_c3_num',
         'bc_num_scaled', 'dst1_num_scaled', 'dst3_num_scaled' ,
         'DSTNIDEP', 'DSTNICNT', 'DSTNIIMM',
         'BCNIDEP', 'BCNICNT', 'BCNIIMM', 'NUMICE10s', 'NUMIMM10sDST', 'NUMIMM10sBC',
         'MPDI2V', 'MPDI2W','QISEDTEN', 'NIMIX_HET', 'NIMIX_CNT', 'NIMIX_IMM', 'NIMIX_DEP',
         'MNUDEPO', 'NNUCCTO', 'NNUCCCO', 'NNUDEPO', 'NIHOMOO','HOMOO'
TXT2

# Use COSP only for isotherm coords, requires modded cosp_simulator.F90 file as SourceMods
if [ $run_type = fouryear ] ; then 

# cosp_amwg needed, I don't think so?
#  cosp_amwg = .false.
#  cosp_llidar_sim = .true.
#  cosp_ncolumns = 10
#  cosp_nradsteps = 3
# Only use need COSP functions to save computation time (cosp_active). Add SLF isotherms (slf_isotherms)

# The CESM2 nudging options should be taken from another file in order to be organized and efficient.
cat <<COSP_SPECS >> user_nl_cam
&cospsimulator_nl
 cosp_active = .true.
 cosp_amwg = .false.
 cosp_ncolumns = 10
 cosp_nradsteps = 3
&slfsimulator_nl
 slf_isotherms = .true.
COSP_SPECS
sed cesm_nudges.txt > user_nl_cam # copy CESM2 nudging nl_vars in

fi
# OPTIONAL: Nudge winds (pt. 2)
# user_nl_cam additions related to nudging. Specify winds, set relax time, set first wind field file, path to all windfield files
# Setting drydep_method resolves an error that arises when using the NF2000climo compset
if [ $nudge_winds = true ] ; then # 

# Strings formatted to give correct startdate and resolution directories (assuming they exist)
#  drydep_method = 'xactive_atm'
cat <<TXT3 >> user_nl_cam
&metdata_nl
 met_nudge_only_uvps = .true.
 met_data_file= "/cluster/shared/noresm/inputdata/noresm-only/inputForNudging/$nudgedir/$startdate.nc"
 met_filenames_list = "/cluster/shared/noresm/inputdata/noresm-only/inputForNudging/$nudgedir/fileList3.txt"
 met_rlx_time = 6
&cam_initfiles_nl
 bnd_topo = "/cluster/shared/noresm/inputdata/noresm-only/inputForNudging/$nudgedir/ERA_bnd_topo.nc"
TXT3

fi

if [ $record_mar_input = true ] ; then # Output additional history files with forcing input for MAR (Stefan)

cat <<MAR_CAM >> user_nl_cam
fincl2 = 'T:I','PS:I','Q:I','U:I','V:I'
nhtfr(2) = -6
fincl3 = 'SST:I'
nhtfr(3) = -24
MAR_CAM

cat <<MAR_CICE >> user_nl_cice
fincl3 = 'f_aice:I'
nhtfr(3) = -24
MAR_CICE

fi
# missing sea ice concentration (likely related to a different module)

exit 1

# build, create *_in files under run/
./case.build

exit 1

# Submit the case
./case.submit
