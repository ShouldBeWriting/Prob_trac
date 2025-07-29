\==================================================================
HCP‑STYLE STRUCTURAL & TRACTOGRAPHY PIPELINE – README (v1.0)
============================================================

This repository contains two Bash scripts that turn raw Human Connectome‑style MRI data into pre‑processed surfaces, masks, and whole‑brain tractograms ready for network analysis. Before running either script, **please read the dependency notes below—especially the HCP folder mapping requirement and the customised MRtrix3 build**.

---

1. FILES IN THIS REPO

---

•  Johns\_HCP\_prefreesurfer        – Structural preprocessing wrapper around the HCP *PreFreeSurfer* pipeline.
•  det\_trac.sh                    –  Anatomically‑constrained tractography pipeline built on MRtrix3.

---

2. HIGH‑LEVEL WORKFLOW

---

Step 1  (structural):  Johns\_HCP\_prefreesurfer
Step 2  (diffusion) :  det\_trac.sh  → tractograms + connectomes

Each script can be run separately via Slurm or locally; logs are written per subject.

---

3. CRITICAL DEPENDENCIES & VERSIONS

---

•  FSL 6.0.7 or later
•  FreeSurfer 7.4 or later
•  gradunwarp ≥ 1.2
•  SynthStrip (part of FreeSurfer or standalone PyPI package)
•  Python ≥ 3.11
•  **MRtrix3 3.0.4 — *must be installed in a virtual/conda environment* AND compiled from the patched source (see below).**
•  CUDA 11+ (optional, for GPU eddy & SynthStrip)
•  **CBIG toolbox** (clone [https://github.com/ThomasYeoLab/CBIG](https://github.com/ThomasYeoLab/CBIG)) – required for the *Schaefer* functional atlas used in downstream connectome generation

---

4. ***HCP FOLDER MAPPING REQUIREMENT***

---

`Johns_HCP_prefreesurfer` will only run if the input subject already sits in the **exact Human Connectome Project directory structure**. If your raw data are BIDS, DICOM, or any other layout, you must first create a **mapping file** and convert the data via **QuNex**:

```
qunex convert-dicom \
      --hcp-mapping <mapping.tsv> \
      --study <HCP_STUDY_FOLDER>
```

Refer to *“HCP Pipeline Mapping”* in the QuNex documentation for details on building `mapping.tsv`. The script checks for the canonical folders, e.g.

```
<study>/unprocessed/3T/T1w_MPR1/<ID>_3T_T1w_MPR1.nii.gz
<study>/unprocessed/3T/Diffusion/<ID>_3T_DWI_dirXX.nii.gz
```

If these are missing the job will abort with an error.

---

5. ***MRTRIX3 BUILD & 5TTGEN PATCH***

---

`det_trac.sh` relies heavily on MRtrix3 and, by default, calls:

•  dwifslpreproc / dwibiascorrect
•  5ttgen                              ← **customised**
•  tckgen (ACT deterministic)
•  tcksift

For reproducibility and to avoid module pollution on multi‑user clusters, we recommend:

```
# create a fresh environment
conda create -n mrtrix3-3.0.4 gcc cmake python=3.11
conda activate mrtrix3-3.0.4

# clone patched source (includes white‑matter‑hyperintensity 5th tissue
git clone https://github.com/yourlab/mrtrix3-wm5tt.git
cd mrtrix3-wm5tt && ./configure && ./build
```

Patch summary:

```
* File modified: `lib/mrtrix3/_5ttgen/hsvs.py`
* Behaviour: adds **white matter hyperintensities (WMH)** as **the 5th tissue type** in the output 5‑TT image so that downstream ACT uses true five‑tissue RFs (GM, CSF, deep GM, sub‑cortical, **WM**); ordinary white matter remains tissue 1.
* Implementation: edit `lib/mrtrix3/_5ttgen/hsvs.py` and modify the **ASEG_STRUCTURES** list:
```

```python
ASEG_STRUCTURES = [ ( 5,  4, 'Left-Inf-Lat-Vent'),
                    (14,  4, '3rd-Ventricle'),
                    (15,  4, '4th-Ventricle'),
                    (24,  4, 'CSF'),
                    (25,  5, 'Left-Lesion'),
                    (30,  4, 'Left-vessel'),
                    (44,  4, 'Right-Inf-Lat-Vent'),
                    (57,  5, 'Right-Lesion'),
                    (62,  4, 'Right-vessel'),
                    (72,  4, '5th-Ventricle')
                    (77,  5, ‘WM-Hypointensities’)
                    (250, 3, 'Fornix') ]
```


Make sure `${MRTRIX3_HOME}/bin` is first in `PATH` when you call `det_trac.sh`.

---

6. QUICK START EXAMPLES

---

# 1. Structural PreFreeSurfer stage

sbatch Johns\_HCP\_prefreesurfer&#x20;
-s /data/hcp\_study&#x20;
-i SUB‑001&#x20;
-c /path/to/scripts&#x20;
-a /path/to/atlas

# 2. Deterministic tractography

source activate mrtrix3-3.0.4
sbatch det\_trac.sh&#x20;
-s /data/hcp\_study&#x20;
-i SUB‑001&#x20;
-c /path/to/CBIG-master&#x20;
-d /scratch/dwi\_work&#x20;
-r /scratch/results

---

7. OUTPUT FOLDERS

---

•  <study>/T1w/                            – recon‑all & surfaces (Johns\_HCP\_prefreesurfer)
•  <results>/det\_trac\_results/<ID>/        – tractograms, connectomes, QC
•  <logs>/<script>/<ID>\_YYYYMMDD‑HHMM.log  – run‑time logs

---

8. TROUBLESHOOTING

---

* **"Folder not found"** – check your QuNex mapping file; rerun `convert-dicom`.
* **"5ttgen: Unknown tissue type 5"** – you are using stock MRtrix; rebuild from the patched fork.
* **GPU eddy fails** – confirm CUDA & driver versions or fall back to CPU by passing `--no‑gpu`.

---

9. CITATION

---

If you use this pipeline, please cite:

* Glasser et al., 2013 – *The minimal preprocessing pipelines for the Human Connectome Project*
* Tournier et al., 2019 – *MRtrix3: A fast, flexible and open‑source framework for medical image processing and visualisation*
* Hoopes et al., 2022 – *SynthStrip: Skull‑stripping for any brain MRI* (MIDL)

---

## Maintainer: John Broulidakis (jbroulidakis_AT_gmail.com ; john.broulidakis_AT_psy.ox.ac.uk)  •   Last update: 29‑Jul‑2025
