#!/usr/bin/env bash
# 02_step2.sh — regenie step 2: per-chromosome association testing
#
# Submits one Swiss Army Knife job per chromosome (up to 22 parallel jobs).
# Requires 01_step1.sh to have completed successfully.
#
# Usage:
#   bash 02_step2.sh [--chr CHR]   # run a single chromosome (for testing)
#   bash 02_step2.sh               # run all chromosomes 1-22
#
# Outputs uploaded to ${OUTPUT_DIR}/:
#   step2_chr{CHR}_AnyPE.regenie.gz  (and for other phenotypes)

set -euo pipefail
source "$(dirname "$0")/config.sh"

# Parse optional --chr argument
CHRS="${AUTOSOMES}"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --chr) CHRS="$2"; shift 2 ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

JOB_IDS=()

for CHR in ${CHRS}; do
    echo "Submitting step 2 job for chromosome ${CHR}..."

    CMD=$(cat << REGENIE_CMD
set -eo pipefail

# Download step 1 LOCO files and build pred.list with local paths
# Regenie names LOCO files step1_output_{i}.loco.gz (single phenotype) or
# step1_output_{PHENO}_{i}.loco.gz (multiple phenotypes); download the pred.list
# from RAP and rewrite paths to local filenames
dx download "${OUTPUT_DIR}/step1_output/step1_output_${PHENO_COLS}_pred.list" -o step1_pred.list
> step1_pred_local.list
while IFS=' ' read -r name path; do
    fname="\${path##*/}"
    dx download "${OUTPUT_DIR}/step1_output/\${fname}" -o "\${fname}"
    echo "\${name} \${fname}" >> step1_pred_local.list
done < step1_pred.list

# Download imputed genotypes for this chromosome (pgen format)
dx download "${IMPUTED_DIR}/ukb500k_c${CHR}_maf005_qced_pgen.pgen" -o chr${CHR}.pgen
dx download "${IMPUTED_DIR}/ukb500k_c${CHR}_maf005_qced_pgen.pvar" -o chr${CHR}.pvar
dx download "${IMPUTED_DIR}/ukb500k_c${CHR}_maf005_qced_pgen.psam" -o chr${CHR}.psam

# Download phenotype file
dx download "${PHENO_FILE}" -o pheno.tsv

mkdir -p step2_output

regenie \
    --step 2 \
    --pgen chr${CHR} \
    --ref-first \
    --pred step1_pred_local.list \
    --phenoFile pheno.tsv \
    --phenoColList "${PHENO_COLS}" \
    --covarFile pheno.tsv \
    --covarColList "${COVAR_COLS}" \
    --bt \
    --af-cc \
    --bsize 400 \
    --minINFO 0.8 \
    --minMAC 20 \
    --firth --approx --firth-se \
    --pThresh 0.05 \
    --chr ${CHR} \
    --out step2_output/step2_chr${CHR} \
    --threads 8 \
    --gz

# Remove inputs so SAK only auto-uploads step 2 outputs
rm -f chr${CHR}.pgen chr${CHR}.pvar chr${CHR}.psam pheno.tsv
rm -f step1_pred.list step1_pred_local.list *.loco.gz

REGENIE_CMD
    )

    JOB_ID=$(dx run app-swiss-army-knife \
        --instance-type "${STEP2_INSTANCE}" \
        --priority normal \
        -icmd="${CMD}" \
        --name "regenie_step2_chr${CHR}" \
        --destination "${OUTPUT_DIR}" \
        -y --brief --detach)

    echo "  chr${CHR}: ${JOB_ID}"
    JOB_IDS+=("${JOB_ID}")
done

echo ""
echo "${#JOB_IDS[@]} step 2 jobs submitted."
printf '%s\n' "${JOB_IDS[@]}" > step2_job_ids.txt

echo "Monitor progress with:"
echo "  dx find jobs --name 'regenie_step2*' --state running"
echo ""
echo "Wait for all jobs to complete:"
echo "  dx wait \$(cat step2_job_ids.txt | tr '\n' ' ')"
