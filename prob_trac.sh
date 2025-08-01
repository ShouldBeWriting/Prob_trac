#!/bin/bash
#SBATCH --job-name=prob_track
#SBATCH --partition=gpu_long   # keep the CUDA-eddy GPU queue
#SBATCH --nodes=1              # single shared-memory job
#SBATCH --ntasks=1             # one Slurm task
#SBATCH --cpus-per-task=10     # 10 OpenMP / MRtrix threads
#SBATCH --gres=gpu:1           # one GPU for eddy-cuda
#SBATCH --mem=32G              # enough RAM for 20 M streamlines + MRtrix

set -euo pipefail  

usage() {
  echo "Usage: $0 -s /path/to/dwi/directory \\
               -i subjectID \\
               -c /path/to/CBIG-master/ \\
               -d /path/to/hcp/directory \\
               -r /path/to/output/of/script \\
               [-g]"
  echo "  -g    Enable Gibbs ringing correction (mrdegibbs) before topup"
  exit 1
}

use_mrdegibbs=0

while getopts "s:i:c:d:r:g?" opt; do
    case $opt in
        s) dwi=${OPTARG} ;;
        i) id=${OPTARG} ;;
        c) script=${OPTARG} ;;
        d) study_folder=${OPTARG} ;;
        r) results=${OPTARG} ;;
        g) use_mrdegibbs=1 ;;
        *) usage ;;
    esac
done

if [[ -z "${study_folder:-}" || -z "${id:-}" || -z "${script:-}" || -z "${dwi:-}" || -z "${results:-}" ]]; then
    usage
fi

echo "Study Folder: ${study_folder}"
echo "ID: ${id}"
if [ "$use_mrdegibbs" -eq 1 ]; then
    echo "Gibbs correction: ENABLED"
else
    echo "Gibbs correction: disabled"
fi

source_dir="/vols/Data/husain_lab/Pablo_scripts"
log_dir="${results}"
participant_folder="${dwi}/${id}"
mkdir -p "${participant_folder}/dwi"
mkdir -p "${participant_folder}/T1"
mkdir -p  "${participant_folder}/T1/reg_tmp"
mkdir -p "${log_dir}"
timestamp=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="${participant_folder}/${id}_tractography_${timestamp}.log"
exec > "${LOG_FILE}" 2>&1

echo "========================================"
echo "Tractography Processing Started at $(date)"
echo "Participant ID: ${id}"
echo "Study Folder: ${study_folder}"
echo "Log File: ${LOG_FILE}"
echo "========================================"

HCP_anat="${study_folder}/${id}/sessions/${id}/hcp/${id}/T1w"
HCP_raw="${study_folder}/${id}/sessions/${id}/nii"
HCP_free="${study_folder}/${id}/sessions/${id}/hcp/${id}/T1w/${id}"
dest_dir="${results}"
CBIG_CODE_DIR="${script}"

a1=${HCP_raw}/13.nii.gz
a2=${HCP_raw}/14.nii.gz
a3=${HCP_raw}/13.bval
a4=${HCP_raw}/13.bvec
a5=${HCP_raw}/14.bval
a6=${HCP_raw}/14.bvec
a7=${HCP_anat}/T1w_acpc_dc_restore_brain.nii.gz
a8=${HCP_anat}/T1w_acpc_dc_restore.nii.gz

csvFile="${log_dir}/included_subjects_outlier.csv"
excludedCsvFile="${log_dir}/excluded_subjects_outlier.csv"


module load Miniconda3
module load fsl
module load freesurfer
module load ANTs
export QT_XCB_GL_INTEGRATION=""
source /cvmfs/software.fmrib.ox.ac.uk/eb/el9/software/Miniconda3/24.1.2-0/etc/profile.d/conda.sh
conda activate mrtrix3_env
export SUBJECTS_DIR="${study_folder}/${id}/sessions/${id}/hcp/${id}/T1w"


if [ ! -f "${participant_folder}/dwi/acqp.txt" ]; then
    cp "${source_dir}/acqp.txt" "${participant_folder}/dwi/acqp.txt" || { echo "Failed to copy acqp.txt from ${source_dir}"; exit 1; }
fi  

echo -e "\e[31m## ## ## ## RUNNING STAGE 1 ON ${id} ## ## ## ##\e[0m"

if [ ! -f "${participant_folder}/dwi/dwi.nii.gz" ] ||
   [ ! -f "${participant_folder}/dwi/dwi_PA.nii.gz" ] ||
   [ ! -f "${participant_folder}/dwi/bval" ] ||
   [ ! -f "${participant_folder}/dwi/bvec" ] ||
   [ ! -f "${participant_folder}/dwi/PA.bval" ] ||
   [ ! -f "${participant_folder}/dwi/index.txt" ] ||
   [ ! -f "${participant_folder}/dwi/acqp.txt" ] ||
   [ ! -f "${participant_folder}/dwi/PA.bvec" ]; then
  
    echo "Files not found in ${participant_folder}/dwi/. Copying now..."
  
    cp "${a1}" "${participant_folder}/dwi/dwi.nii.gz"
    cp "${a2}" "${participant_folder}/dwi/dwi_PA.nii.gz"
    cp "${a3}" "${participant_folder}/dwi/bval"
    cp "${a4}" "${participant_folder}/dwi/bvec"
    cp "${a5}" "${participant_folder}/dwi/PA.bval"
    cp "${source_dir}/acqp.txt" "${participant_folder}/dwi/acqp.txt"
    cp "${source_dir}/index.txt" "${participant_folder}/dwi/index.txt"
    cp "${a6}" "${participant_folder}/dwi/PA.bvec"
fi

if [ ! -f "${participant_folder}/T1/T1w_acpc_dc_restore_brain.nii.gz" ] ||
   [ ! -f "${participant_folder}/T1/T1w_acpc_dc_restore.nii.gz" ]; then
  
    echo "T1 files not found in ${participant_folder}/T1/ Copying now..."
  
    cp "${a7}" "${participant_folder}/T1/T1w_acpc_dc_restore_brain.nii.gz"
    cp "${a8}" "${participant_folder}/T1/T1w_acpc_dc_restore.nii.gz"
fi

## Set FreeSurfer DIR
export SUBJECTS_DIR="${study_folder}/${id}/sessions/${id}/hcp/${id}/T1w"


# conditional nodif extraction with optional Gibbs ringing correction
if [ "$use_mrdegibbs" -eq 1 ]; then
    echo "-----> Running mrdegibbs correction pipeline for ${id}"
    mrconvert "${participant_folder}/dwi/dwi.nii.gz" "${participant_folder}/T1/reg_tmp/dwi.mif" -fslgrad "${participant_folder}/dwi/bvec" "${participant_folder}/dwi/bval" -force
    mrdegibbs "${participant_folder}/T1/reg_tmp/dwi.mif"  "${participant_folder}/T1/reg_tmp/dwi_gib.mif" -force
    mrconvert "${participant_folder}/T1/reg_tmp/dwi_gib.mif" "${participant_folder}/T1/reg_tmp/dwi_gib.nii.gz" -export_grad_fsl "${participant_folder}/T1/reg_tmp/bvecs_mr" "${participant_folder}/T1/reg_tmp/bvals_mr" -force
    fslroi "${participant_folder}/T1/reg_tmp/dwi_gib.nii.gz" "${participant_folder}/dwi/nodif" 0 1
else
    fslroi "${participant_folder}/dwi/dwi.nii.gz" "${participant_folder}/dwi/nodif" 0 1
fi

fslroi "${participant_folder}/dwi/dwi_PA.nii.gz" "${participant_folder}/dwi/nodif_PA" 0 1
fslmerge -t "${participant_folder}/dwi/AP_PA_b0.nii.gz" "${participant_folder}/dwi/nodif" "${participant_folder}/dwi/nodif_PA"
topup --imain="${participant_folder}/dwi/AP_PA_b0.nii.gz" --datain="${participant_folder}/dwi/acqp.txt" --config="${FSLDIR}/etc/flirtsch/b02b0.cnf" --out="${participant_folder}/dwi/topup_AP_PA_b0"
applytopup --imain="${participant_folder}/dwi/nodif,${participant_folder}/dwi/nodif_PA" --topup="${participant_folder}/dwi/topup_AP_PA_b0" --datain="${participant_folder}/dwi/acqp.txt" --inindex=1,2 --out="${participant_folder}/dwi/hifi_nodif"
mri_synthstrip -i "${participant_folder}/dwi/hifi_nodif.nii.gz" -m "${participant_folder}/dwi/nodif_brain_mask.nii.gz" -g 

# choose input DWI and gradient files depending on whether Gibbs correction was requested
if [ "${use_mrdegibbs:-0}" -eq 1 ]; then
    DWI_IN="${participant_folder}/T1/reg_tmp/dwi_gib.nii.gz"
else
    DWI_IN="${participant_folder}/dwi/dwi.nii.gz"
fi

# run eddy on the selected image/gradients
eddy --imain="${DWI_IN}" \
     --mask="${participant_folder}/dwi/nodif_brain_mask.nii.gz" \
     --index="${participant_folder}/dwi/index.txt" \
     --acqp="${participant_folder}/dwi/acqp.txt" \
     --bvecs="${participant_folder}/dwi/bvec" \
     --bvals="${participant_folder}/dwi/bval" \
     --fwhm=0 \
     --topup="${participant_folder}/dwi/topup_AP_PA_b0" \
     --flm=quadratic \
     --out="${participant_folder}/dwi/data" \
     --cnr_maps \
     --repol \
     --mporder=16

echo -e "\e[31m## ## ## ## RUNNING STAGE 2 ON ${id} ## ## ## ##\e[0m"
 
# QC check for motion during scan. Will skip processing if > 10% of all slices are outliers as detected during eddy correction.
outlierMapFile="${participant_folder}/dwi/data.eddy_outlier_map"
totalSlices=$(mrinfo "${participant_folder}/dwi/data.nii.gz" | grep Dimensions | awk '{print $6 * $8}')
totalOutliers=$(awk 'BEGIN {sum=0} { for(i=1;i<=NF;i++) sum += $i } END { print sum }' "${outlierMapFile}")

percentageOutliers=$(awk "BEGIN { printf \"%.2f\", (${totalOutliers} / ${totalSlices}) * 100 }")

echo "Subject $id:"
echo "Total slices: $totalSlices"
echo "Corrupted slices: $totalOutliers"
echo "Percentage corrupted: $percentageOutliers%"

# Check if percentage of outliers exceeds threshold
if (( $(echo "$percentageOutliers > 10" | bc -l) )); then
    echo "Subject $id should be removed due to excessive motion or corrupted slices."
    if [ ! -f "$excludedCsvFile" ]; then
        echo "SubjectID,PercentageOutliers" > "$excludedCsvFile"
    fi
    echo "$id,$percentageOutliers" >> "$excludedCsvFile"
    exit 1
else
    echo "Subject $id is within acceptable limits."
    if [ ! -f "$csvFile" ]; then
        echo "SubjectID,PercentageOutliers" > "$csvFile"
    fi
fi


echo "$id,$percentageOutliers" >> "$csvFile"

mrconvert "${participant_folder}/dwi/data.nii.gz" "${participant_folder}/dwi/eddy_corrected_data.mif" -fslgrad "${participant_folder}/dwi/bvec" "${participant_folder}/dwi/bval" -force
dwibiascorrect ants "${participant_folder}/dwi/eddy_corrected_data.mif" "${participant_folder}/dwi/eddy_corrected_data_unbiased.mif" -bias ${participant_folder}/dwi/bias.mif -force
dwi2response dhollander "${participant_folder}/dwi/eddy_corrected_data_unbiased.mif" "${participant_folder}/dwi/wm.txt" "${participant_folder}/dwi/gm.txt" "${participant_folder}/dwi/csf.txt" -voxels "${participant_folder}/dwi/voxels.mif" -force
dwi2fod msmt_csd "${participant_folder}/dwi/eddy_corrected_data_unbiased.mif" -mask "${participant_folder}/dwi/mask.mif" "${participant_folder}/dwi/wm.txt" "${participant_folder}/dwi/wmfod.mif" "${participant_folder}/dwi/gm.txt" "${participant_folder}/dwi/gmfod.mif" "${participant_folder}/dwi/csf.txt" "${participant_folder}/dwi/csffod.mif" -force || { echo "dwi2fod failed for ${id}"; exit 1; }
mrconvert -coord 3 0 "${participant_folder}/dwi/wmfod.mif" -force - | mrcat "${participant_folder}/dwi/csffod.mif" "${participant_folder}/dwi/gmfod.mif" - "${participant_folder}/dwi/vf.mif" -force
mtnormalise "${participant_folder}/dwi/wmfod.mif" "${participant_folder}/dwi/wmfod_norm.mif" "${participant_folder}/dwi/gmfod.mif" "${participant_folder}/dwi/gmfod_norm.mif" "${participant_folder}/dwi/csffod.mif" "${participant_folder}/dwi/csffod_norm.mif" -mask "${participant_folder}/dwi/mask.mif" -force || { echo "mtnormalise failed for ${id}. Skipping."; exit 1; }

## Generate a 5-tissue-type (5TT) segmentation from the T1 image
echo "----> Generating 5tt_nocoreg.mif..."
5ttgen hsvs "${HCP_free}" "${participant_folder}/dwi/5tt_nocoreg.mif" -force

if [ ! -f "${participant_folder}/dwi/5tt_nocoreg.mif" ]; then
    echo "**** 5ttgen failed for ${id}. Skipping. ****"
    exit 1
fi

mkdir -p "${participant_folder}/dwi/xmfs"

dwiextract "${participant_folder}/dwi/eddy_corrected_data_unbiased.mif" - -bzero | mrmath - mean "${participant_folder}/dwi/mean_b0.mif" -axis 3 -force
mrconvert "${participant_folder}/dwi/mean_b0.mif" "${participant_folder}/T1/reg_tmp/mean_b0.nii.gz" -force
mrconvert "${participant_folder}/dwi/5tt_nocoreg.mif" "${participant_folder}/T1/reg_tmp/5tt_nocoreg.nii.gz" -force
bbregister --s "${id}" --mov "${participant_folder}/T1/reg_tmp/mean_b0.nii.gz" --reg "${participant_folder}/dwi/xmfs/mean_b0_to_T1_bbreg.lta" --dti
lta_convert --inlta "${participant_folder}/dwi/xmfs/mean_b0_to_T1_bbreg.lta" --outitk "${participant_folder}/dwi/xmfs/mean_b0_to_T1_bbreg_itk.txt"
transformconvert "${participant_folder}/dwi/xmfs/mean_b0_to_T1_bbreg_itk.txt" itk_import "${participant_folder}/dwi/xmfs/mean_b0_to_T1_mrtrix.txt" -force
mrtransform "${participant_folder}/T1/reg_tmp/5tt_nocoreg.nii.gz" -linear "${participant_folder}/dwi/xmfs/mean_b0_to_T1_mrtrix.txt" -inverse -interp nearest "${participant_folder}/T1/reg_tmp/5tt_coreg.nii.gz" -force
mrconvert "${participant_folder}/T1/reg_tmp/5tt_coreg.nii.gz" "${participant_folder}/dwi/5tt_coreg.mif" -force

5tt2gmwmi "${participant_folder}/dwi/5tt_coreg.mif" "${participant_folder}/dwi/gmwmSeed_coreg.mif" -force


mkdir -p "${participant_folder}/dwi/dwi2response-tmp"
mkdir -p "${participant_folder}/dwi/average_diffusion_response"


echo "----> Generating diffusion response functions from each tissue type"
mrconvert ${participant_folder}/dwi/eddy_corrected_data.mif ${participant_folder}/dwi/dwi2response-tmp/dwi.mif -strides 0,0,0,1 -force
mrconvert ${participant_folder}/dwi/5tt_coreg.mif ${participant_folder}/dwi/dwi2response-tmp/5tt.mif -force
dwi2mask ${participant_folder}/dwi/dwi2response-tmp/dwi.mif ${participant_folder}/dwi/dwi2response-tmp/mask.mif -force
dwi2tensor ${participant_folder}/dwi/dwi2response-tmp/dwi.mif - -mask ${participant_folder}/dwi/dwi2response-tmp/mask.mif | tensor2metric - -fa ${participant_folder}/dwi/dwi2response-tmp/fa.mif -vector ${participant_folder}/dwi/dwi2response-tmp/dars.mif -force
mrtransform ${participant_folder}/dwi/dwi2response-tmp/5tt.mif ${participant_folder}/dwi/dwi2response-tmp/5tt_regrid.mif -template ${participant_folder}/dwi/dwi2response-tmp/fa.mif -interp linear -force
mrconvert ${participant_folder}/dwi/dwi2response-tmp/5tt_regrid.mif - -coord 3 2 -axes 0,1,2 | mrcalc - 0.95 -gt ${participant_folder}/dwi/dwi2response-tmp/mask.mif -mult ${participant_folder}/dwi/dwi2response-tmp/wm_mask.mif -force
mrconvert ${participant_folder}/dwi/dwi2response-tmp/5tt_regrid.mif - -coord 3 0 -axes 0,1,2 | mrcalc - 0.95 -gt ${participant_folder}/dwi/dwi2response-tmp/fa.mif 0.2 -lt -mult ${participant_folder}/dwi/dwi2response-tmp/mask.mif -mult ${participant_folder}/dwi/dwi2response-tmp/gm_mask.mif -force
mrconvert ${participant_folder}/dwi/dwi2response-tmp/5tt_regrid.mif - -coord 3 3 -axes 0,1,2 | mrcalc - 0.95 -gt ${participant_folder}/dwi/dwi2response-tmp/fa.mif 0.2 -lt -mult ${participant_folder}/dwi/dwi2response-tmp/mask.mif -mult ${participant_folder}/dwi/dwi2response-tmp/csf_mask.mif -force
mrconvert ${participant_folder}/dwi/dwi2response-tmp/5tt_regrid.mif - -coord 3 4 -axes 0,1,2 | mrcalc - 0.95 -gt ${participant_folder}/dwi/dwi2response-tmp/mask.mif -mult ${participant_folder}/dwi/dwi2response-tmp/wmh_mask.mif -force 
dwi2response tournier ${participant_folder}/dwi/dwi2response-tmp/dwi.mif ${participant_folder}/dwi/dwi2response-tmp/wm_ss_response.txt -mask ${participant_folder}/dwi/dwi2response-tmp/wm_mask.mif -voxels ${participant_folder}/dwi/dwi2response-tmp/wm_sf_mask.mif -force
dwi2response tournier ${participant_folder}/dwi/dwi2response-tmp/dwi.mif ${participant_folder}/dwi/dwi2response-tmp/wmh_ss_response.txt -mask ${participant_folder}/dwi/dwi2response-tmp/wmh_mask.mif -voxels ${participant_folder}/dwi/dwi2response-tmp/wmh_sf_mask.mif -force
amp2response ${participant_folder}/dwi/dwi2response-tmp/dwi.mif ${participant_folder}/dwi/dwi2response-tmp/wm_sf_mask.mif ${participant_folder}/dwi/dwi2response-tmp/dars.mif ${participant_folder}/dwi/average_diffusion_response/wm.txt -shells 5,999,1998 -force
amp2response ${participant_folder}/dwi/dwi2response-tmp/dwi.mif ${participant_folder}/dwi/dwi2response-tmp/wmh_sf_mask.mif ${participant_folder}/dwi/dwi2response-tmp/dars.mif ${participant_folder}/dwi/average_diffusion_response/wmh.txt -shells 5,999,1998 -force
amp2response ${participant_folder}/dwi/dwi2response-tmp/dwi.mif ${participant_folder}/dwi/dwi2response-tmp/gm_mask.mif ${participant_folder}/dwi/dwi2response-tmp/dars.mif ${participant_folder}/dwi/average_diffusion_response/gm.txt -shells 5,999,1998 -isotropic -force
amp2response ${participant_folder}/dwi/dwi2response-tmp/dwi.mif ${participant_folder}/dwi/dwi2response-tmp/csf_mask.mif ${participant_folder}/dwi/dwi2response-tmp/dars.mif ${participant_folder}/dwi/average_diffusion_response/csf.txt -shells 5,999,1998 -isotropic -force
mv ${participant_folder}/dwi/dwi2response-tmp/wmh_mask.mif ${participant_folder}/dwi/wmh_mask.mif


echo "Creating 20M streamlines and running ACT"
tckgen -act "${participant_folder}/dwi/5tt_coreg.mif" -backtrack \
  -seed_gmwmi "${participant_folder}/dwi/gmwmSeed_coreg.mif" -nthreads 10 \
  -maxlength 250 -cutoff 0.06 -select 20000000 -info \
  "${participant_folder}/dwi/wmfod_norm.mif" "${participant_folder}/dwi/tracks_20M.tck" -force || { echo "tckgen failed for ${id}. Skipping."; exit 1; }
tckedit "${participant_folder}/dwi/tracks_20M.tck" -number 200k "${participant_folder}/dwi/smallerTracks_200k.tck" -force || { echo "tckedit failed for ${id}. Skipping."; exit 1; }
tcksift2 -act "${participant_folder}/dwi/5tt_coreg.mif" \
  -out_mu "${participant_folder}/dwi/sift_mu.txt" \
  -out_coeffs "${participant_folder}/dwi/sift_coeffs.txt" \
  -nthreads 10 \
  "${participant_folder}/dwi/tracks_20M.tck" "${participant_folder}/dwi/wmfod_norm.mif" \
  "${participant_folder}/dwi/sift_2M.txt" -force || { echo "tcksift2 failed for ${id}. Skipping."; exit 1; }

echo -e "\e[31m## ## ## ## RUNNING STAGE 3 ON ${id} ## ## ## ##\e[0m"

echo "-----> Using mris_ca_label to generate individual parcellation using gcs files"
mris_ca_label \
  -l "${SUBJECTS_DIR}/${id}/label/lh.cortex.label" \
  "${id}" lh \
  "${SUBJECTS_DIR}/${id}/surf/lh.sphere.reg" \
  "${CBIG_CODE_DIR}/gcs_schaefer/lh.Schaefer2018_200Parcels_17Networks.gcs" \
  "${SUBJECTS_DIR}/${id}/label/lh.Schaefer2018_200Parcels_17Networks_order.annot"

mris_ca_label \
  -l "${SUBJECTS_DIR}/${id}/label/rh.cortex.label" \
  "${id}" rh \
  "${SUBJECTS_DIR}/${id}/surf/rh.sphere.reg" \
  "${CBIG_CODE_DIR}/gcs_schaefer/rh.Schaefer2018_200Parcels_17Networks.gcs" \
  "${SUBJECTS_DIR}/${id}/label/rh.Schaefer2018_200Parcels_17Networks_order.annot"

echo "------> Generate Schaefer2018 parcellation in volume space"
mri_aparc2aseg \
  --s "${id}" --old-ribbon \
  --o "${HCP_free}/Schaefer2018_200Parcels_17Networks_order_atlas.mgz" \
  --annot Schaefer2018_200Parcels_17Networks_order \
  --rip-unknown

echo "-------> Converting Schaefer2018 parcellation for MRtrix3"
labelconvert \
  "${HCP_free}/Schaefer2018_200Parcels_17Networks_order_atlas.mgz" \
  "${CBIG_CODE_DIR}/stable_projects/brain_parcellation/Schaefer2018_LocalGlobal/Parcellations/project_to_individual/Schaefer2018_200Parcels_17Networks_order_LUT.txt" \
  "${CBIG_CODE_DIR}/yeo_default_2.txt" \
  "${participant_folder}/dwi/${id}_nocoreg_yeo_parcels.mif" \
  -force

echo "****** Transforming parcellation to DWI space ********"
mrtransform \
  "${participant_folder}/dwi/${id}_nocoreg_yeo_parcels.mif" \
  -inverse \
  -linear "${participant_folder}/dwi/xmfs/mean_b0_to_T1_mrtrix.txt" \
  -datatype uint32 \
  "${participant_folder}/dwi/${id}_parcels_coreg_yeo.mif" \
  -force

echo "-----> Building the streamline count connectome (inv node vol scaling)"
tck2connectome \
  -symmetric \
  -zero_diagonal \
  -scale_invnodevol \
  -tck_weights_in "${participant_folder}/dwi/sift_2M.txt" \
  "${participant_folder}/dwi/tracks_20M.tck" \
  "${participant_folder}/dwi/${id}_parcels_coreg_yeo.mif" \
  "${participant_folder}/dwi/${id}_coreg_parcels_yeo.csv" \
  -out_assignment "${participant_folder}/dwi/assignments_${id}_coreg_parcels_yeo.csv" \
  -force

echo "-------> Generating connectivity matrix weighted by mean streamline length..."
tck2connectome \
  "${participant_folder}/dwi/tracks_20M.tck" \
  "${participant_folder}/dwi/${id}_parcels_coreg_yeo.mif" \
  "${participant_folder}/dwi/${id}_distances_yeo.csv" \
  -scale_length -stat_edge mean \
  -symmetric \
  -zero_diagonal \
  -tck_weights_in "${participant_folder}/dwi/sift_2M.txt" \
  -force

echo "-------> Generating connectivity matrix weighted by mean streamline FA..."
dwi2tensor \
  "${participant_folder}/dwi/eddy_corrected_data_unbiased.mif" \
  "${participant_folder}/dwi/dt.mif" \
  -mask "${participant_folder}/dwi/mask.mif" \
  -force

tensor2metric \
  "${participant_folder}/dwi/dt.mif" \
  -fa "${participant_folder}/dwi/FA.mif" \
  -force

mrcalc "${participant_folder}/dwi/FA.mif" -finite \
  "${participant_folder}/dwi/FA.mif" \
  0.0 -if "${participant_folder}/dwi/FA_clean.mif" -force

tcksample "${participant_folder}/dwi/tracks_20M.tck" \
  "${participant_folder}/dwi/FA_clean.mif" \
  "${participant_folder}/dwi/mean_FA_per_streamline.csv" \
  -stat_tck mean \
  -force

tck2connectome \
  -symmetric \
  -zero_diagonal \
  "${participant_folder}/dwi/tracks_20M.tck" \
  "${participant_folder}/dwi/${id}_parcels_coreg_yeo.mif" \
  "${participant_folder}/dwi/${id}_yeo_mean_FA_connectome.csv" \
  -scale_file "${participant_folder}/dwi/mean_FA_per_streamline.csv" \
  -tck_weights_in "${participant_folder}/dwi/sift_2M.txt" \
  -stat_edge mean \
  -force

echo "-------> Saving results"

# Create output directories for diffusion response files
mkdir -p "${results}/det_trac_results/diff_response/wm"
mkdir -p "${results}/det_trac_results/diff_response/gm"
mkdir -p "${results}/det_trac_results/diff_response/csf"
mkdir -p "${results}/det_trac_results/diff_response/whm"
mkdir -p "${results}/det_trac_results/weighted_by_FA_inhyper"
mkdir -p "${results}/det_trac_results/weighted_by_FBC_inhyper"

# Copy the newly generated connectomes
cp "${participant_folder}/dwi/${id}_yeo_mean_FA_connectome.csv" \
   "${results}/det_trac_results/weighted_by_FA_inhyper/${id}_yeo_mean_FA_connectome.csv" || echo "**error copying FA CSV**"
cp "${participant_folder}/dwi/${id}_coreg_parcels_yeo.csv" \
   "${results}/det_trac_results/weighted_by_FBC_inhyper/${id}_coreg_parcels_yeo.csv" || echo "**error copying parcellation CSV**"

# Copy diffusion response function outputs
cp "${participant_folder}/dwi/average_diffusion_response/wm.txt" \
   "${results}/det_trac_results/diff_response/wm/${id}_wm_response.txt" \
   || echo "**error copying WM response**"

cp "${participant_folder}/dwi/average_diffusion_response/gm.txt" \
   "${results}/det_trac_results/diff_response/gm/${id}_gm_response.txt" \
   || echo "**error copying GM response**"

cp "${participant_folder}/dwi/average_diffusion_response/csf.txt" \
   "${results}/det_trac_results/diff_response/csf/${id}_csf_response.txt" \
   || echo "**error copying CSF response**"

cp "${participant_folder}/dwi/average_diffusion_response/wmh.txt" \
   "${results}/det_trac_results/diff_response/whm/${id}_wmh_response.txt" \
   || echo "**error copying WMH response**"

# Clean up temporary files
rm -rf "${participant_folder}/T1/reg_tmp"
rm -rf "${participant_folder}/dwi/dwi2response-tmp"


echo "-------->  generating QC images"
mrconvert ${participant_folder}/dwi/${id}_parcels_coreg_yeo.mif ${participant_folder}/T1/reg_tmp/${id}_parcels_coreg_yeo.nii.gz
fsleyes render -of ${results}/det_trac_results/atlasXmeanb0_reg_check/${id}_AtlasOverMeanb0.png -s ortho ${participant_folder}/T1/reg_tmp/mean_b0.nii.gz ${participant_folder}/T1/reg_tmp/${id}_parcels_coreg_yeo.nii.gz

chmod -R 777 ${results}/*

rm -rf "${participant_folder}/T1/reg_tmp"
rm -rf "${participant_folder}/dwi/dwi2response-tmp"

echo "Processing complete for ${id}."
echo "========================================"
echo "Tractography Processing Ended at $(date)"
echo "========================================"

