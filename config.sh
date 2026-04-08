#!/usr/bin/env bash
# config.sh — configuration for regenie GWAS pipeline
# Source this file from all other scripts: source "$(dirname "$0")/config.sh"

# --- DNAnexus project ---
PROJECT_ID="XXXX"  # replace with your DNAnexus project ID
PROJECT_ROOT="YYYY:" # replace with your DNAnexus project ID root

# --- RAP paths (paths within the DNAnexus project) ---
ARRAY_GENO_DIR="${PROJECT_ROOT}/Bulk/Genotype Results/Genotype calls" # raw array genotypes (before QC) used in step1 of regenie
IMPUTED_DIR="${PROJECT_ROOT}/derived/topmed_qc/v1_20260331" # imputed genotypes (pgen format) used in step2 of regenie; one per chromosome (replace with your QCed imputed data path)
INPUT_DIR="${PROJECT_ROOT}/regenie_input"
OUTPUT_DIR="${PROJECT_ROOT}/regenie_output"

# Array genotype file prefix pattern (one per chromosome):
# ${ARRAY_GENO_DIR}/ukb_cal_chr{CHR}_v2.{bed,bim,fam}

# Imputed pgen file pattern (one per chromosome):
# ${IMPUTED_DIR}/ukb500k_c{CHR}_maf005_qced_pgen.{pgen,pvar,psam}

# --- Phenotype / covariate file ---
# Upload locally with: dx upload psych_exp_phe --path ${INPUT_DIR}/
# replace psych_exp_phe with your own phenotype file
PHENO_FILE="${INPUT_DIR}/psych_exp_phe" 

# Columns in psych_exp_phe: FID IID AnyPE DistressingPE MultiplePE sex age pc1..pc20
PHENO_COLS="AnyPE"  # AnyPE,DistressingPE,MultiplePE
COVAR_COLS="age,sex,$(seq -s, 1 20 | sed -E 's/[0-9]+/pc&/g')"  # age,sex,pc1,pc2,...,pc20

# --- Instance types ---
STEP1_INSTANCE="mem2_ssd2_v2_x32"   # step 1: high-memory, SSD
STEP2_INSTANCE="mem1_ssd1_v2_x16"    # step 2: one per chromosome

# --- Chromosomes ---
AUTOSOMES=$(seq 1 22)
