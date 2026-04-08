# regenie GWAS pipeline

GWAS using regenie on imputed genotypes on the UK Biobank Research Analysis Platform (DNAnexus RAP).

All scripts are run locally and submit Swiss Army Knife (SAK) jobs to RAP.
The scripts are hard coded for binary traits for now.

## Scripts

| Script | Description |
|--------|-------------|
| `config.sh` | Configuration: RAP paths, phenotype/covariate columns, instance types. Source this in all other scripts. |
| `00_prep_genotypes.sh` | Downloads UKB array genotypes (chr1–22), applies QC filters, merges chromosomes with plink1, and LD-prunes with plink2. Outputs `ukb_array_qc.bed/bim/fam` and `samples_keep.txt` to `${INPUT_DIR}`. |
| `01_step1.sh` | Runs regenie step 1 (whole-genome ridge regression) on the QCed array genotypes. Outputs LOCO predictions to `${OUTPUT_DIR}/step1_output`. |
| `02_step2.sh` | Runs regenie step 2 (association testing) on imputed pgen files, one parallel SAK job per chromosome. Outputs per-chromosome `.regenie.gz` files to `${OUTPUT_DIR}/step2_output`. |
| `03_collect_results.sh` | Run locally after step 2. Downloads and merges per-chromosome results into one file per phenotype in `results/`. |
| `test_subset.sh` | Test pipeline on chr21+22 with N=2000 random participants. Two chained SAK jobs: plink2 QC (Job 1) + regenie step 1 & step 2 (Job 2). |

## Pipeline order

```
(config.sh - sourced by all)
    ↓
00_prep_genotypes.sh   — array genotype QC
    ↓
01_step1.sh            — regenie step 1
    ↓
02_step2.sh            — regenie step 2 (22 parallel jobs)
    ↓
03_collect_results.sh  — merge results locally
```

## QC filters (step 1 array genotypes)

- SNP missingness: `--geno 0.1`
- Sample missingness: `--mind 0.1`
- MAF: `--maf 0.01`
- MAC: `--mac 50`
- HWE: `--hwe 1e-15`
- LD pruning: `--indep-pairwise 1000 100 0.9`
