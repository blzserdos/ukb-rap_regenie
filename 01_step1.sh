#!/usr/bin/env bash
# 01_step1.sh — regenie step 1: whole-genome ridge regression
#
# Submits a single Swiss Army Knife job on DNAnexus RAP.
# Requires 00_prep_genotypes.sh to have been run first.
#
# Usage (from local machine with dx CLI logged in):
#   bash 01_step1.sh
#
# Output uploaded to ${OUTPUT_DIR}/:
#   step1_output_pred.list
#   step1_output_AnyPE_1.loco.gz  (and for other phenotypes)

set -euo pipefail
source "$(dirname "$0")/config.sh"

# Command to run inside the Swiss Army Knife container
CMD=$(cat << REGENIE_CMD
set -eo pipefail

# Download inputs
dx download "${INPUT_DIR}/ukb_array_qc.bed" -o ukb_array_qc.bed
dx download "${INPUT_DIR}/ukb_array_qc.bim" -o ukb_array_qc.bim
dx download "${INPUT_DIR}/ukb_array_qc.fam" -o ukb_array_qc.fam
dx download "${PHENO_FILE}" -o pheno.tsv

mkdir -p /tmp/regenie_tmp
mkdir -p step1_output

regenie \
    --step 1 \
    --bed ukb_array_qc \
    --phenoFile pheno.tsv \
    --phenoColList "${PHENO_COLS}" \
    --covarFile pheno.tsv \
    --covarColList "${COVAR_COLS}" \
    --bt \
    --bsize 1000 \
    --lowmem \
    --lowmem-prefix /tmp/regenie_tmp/regenie_tmp \
    --out step1_output/step1_output_${PHENO_COLS} \
    --threads 32 \
    --gz

# Remove inputs so SAK only auto-uploads step 1 outputs
rm -f ukb_array_qc.bed ukb_array_qc.bim ukb_array_qc.fam pheno.tsv

# SAK auto-uploads all files in the working directory to --destination on job completion
REGENIE_CMD
)

echo "Submitting regenie step 1 job..."
JOB_ID=$(dx run app-swiss-army-knife \
    --instance-type "${STEP1_INSTANCE}" \
    --priority normal \
    -icmd="${CMD}" \
    --name "regenie_step1" \
    --destination "${OUTPUT_DIR}" \
    -y --brief)

echo "Step 1 job submitted: ${JOB_ID}"
echo "${JOB_ID}" > step1_job_id.txt
echo "Monitor with: dx watch ${JOB_ID}"
echo "Wait for completion with: dx wait ${JOB_ID}"
