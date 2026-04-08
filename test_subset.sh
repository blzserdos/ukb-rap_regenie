#!/usr/bin/env bash
# test_subset.sh — regenie pipeline test on chr21+22
#
# Submits two chained Swiss Army Knife jobs on RAP:
#   Job 1 (SAK): random sample selection + plink2 genotype QC
#   Job 2 (SAK): regenie step 1 + step 2
#
# Requirements (local): dx CLI only
#
# Usage:
#   bash test_subset.sh [--n-samples 2000]

set -euo pipefail
source "$(dirname "$0")/config.sh"

N_SAMPLES=2000
TEST_CHRS="21 22"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --n-samples) N_SAMPLES="$2"; shift 2 ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# JOB 1: sample selection + plink2 genotype QC (SAK built-in, no image)
# ---------------------------------------------------------------------------
echo "Submitting Job 1 (sample selection + plink2 QC)..."

PLINK_CMD=$(cat << JOBEOF
set -eo pipefail

# ---- Sample selection from FAM file ----
echo "Selecting ${N_SAMPLES} random participants from FAM..."
dx download "${ARRAY_GENO_DIR}/ukb22418_c21_b0_v2.fam" -o chr21.fam
shuf -n ${N_SAMPLES} chr21.fam | awk '{print \$1, \$2}' > samples_subset.txt
echo "  \$(wc -l < samples_subset.txt) samples selected"

# ---- Step 1: merge chr21 + chr22 with plink1 ----
echo "Downloading array genotypes (chr21, chr22)..."
dx download "${ARRAY_GENO_DIR}/ukb22418_c21_b0_v2.bed" -o chr21.bed
dx download "${ARRAY_GENO_DIR}/ukb22418_c21_b0_v2.bim" -o chr21.bim
dx download "${ARRAY_GENO_DIR}/ukb22418_c21_b0_v2.fam" -o chr21.fam --overwrite
dx download "${ARRAY_GENO_DIR}/ukb22418_c22_b0_v2.bed" -o chr22.bed
dx download "${ARRAY_GENO_DIR}/ukb22418_c22_b0_v2.bim" -o chr22.bim
dx download "${ARRAY_GENO_DIR}/ukb22418_c22_b0_v2.fam" -o chr22.fam --overwrite

echo "chr22.bed chr22.bim chr22.fam" > list_beds.txt

plink \
    --bfile chr21 \
    --merge-list list_beds.txt \
    --make-bed \
    --out test_merged

# rm -f chr21.bed chr21.bim chr21.fam chr22.bed chr22.bim chr22.fam

# ---- Step 2: plink2 QC + sample subsetting ----
echo "Running plink2 QC..."
plink2 \
    --bfile test_merged \
    --keep samples_subset.txt \
    --maf 0.01 --mac 100 --geno 0.1 --hwe 1e-15 --mind 0.1 \
    --make-bed \
    --out test_array \
    --threads 4

# rm -f test_merged.bed test_merged.bim test_merged.fam
echo "  Array SNPs: \$(wc -l < test_array.bim)"
JOBEOF
)

JOB1_ID=$(dx run app-swiss-army-knife \
    --instance-type "mem1_ssd1_v2_x8" \
    --priority normal \
    -icmd="${PLINK_CMD}" \
    --name "regenie_test_plink2" \
    --destination "${OUTPUT_DIR}/test" \
    --brief -y)

echo "  Job 1 submitted: ${JOB1_ID}"
echo "  Waiting for Job 1 to complete..."
dx wait "${JOB1_ID}"
echo "  Job 1 done."

# ---------------------------------------------------------------------------
# JOB 2: regenie step 1 + step 2 (regenie Docker image)
# ---------------------------------------------------------------------------
echo "Submitting Job 2 (regenie step 1 + step 2)..."

REGENIE_CMD=$(cat << JOBEOF
set -eo pipefail

# Download array genotype files (auto-uploaded by Job 1 to --destination)
dx download "${OUTPUT_DIR}/test/test_array.bed" -o test_array.bed
dx download "${OUTPUT_DIR}/test/test_array.bim" -o test_array.bim
dx download "${OUTPUT_DIR}/test/test_array.fam" -o test_array.fam --overwrite
dx download "${OUTPUT_DIR}/test/samples_subset.txt" -o samples_subset.txt

# Download full phenotype file (subset restricted via --keep in regenie)
dx download "${PHENO_FILE}" -o pheno.tsv

# ---- Step 1 ----
echo "Running regenie step 1..."
mkdir -p step1_test /tmp/regenie_tmp

regenie \
    --step 1 \
    --bed test_array \
    --keep samples_subset.txt \
    --phenoFile pheno.tsv \
    --phenoColList "${PHENO_COLS}" \
    --covarFile pheno.tsv \
    --covarColList "${COVAR_COLS}" \
    --bt \
    --bsize 1000 \
    --lowmem \
    --lowmem-prefix /tmp/regenie_tmp/regenie_tmp \
    --out step1_test/step1_test_${PHENO_COLS} \
    --threads 8 \
    --gz

# ---- Step 2 (chr21 + chr22 sequentially) ----
echo "Running regenie step 2..."
for CHR in ${TEST_CHRS}; do
    dx download "${IMPUTED_DIR}/ukb500k_c\${CHR}_maf005_qced_pgen.pgen" -o "imp_test\${CHR}.pgen"
    dx download "${IMPUTED_DIR}/ukb500k_c\${CHR}_maf005_qced_pgen.pvar" -o "imp_test\${CHR}.pvar"
    dx download "${IMPUTED_DIR}/ukb500k_c\${CHR}_maf005_qced_pgen.psam" -o "imp_test\${CHR}.psam"

    mkdir -p step2_output

    regenie \
        --step 2 \
        --pgen "imp_test\${CHR}" \
        --ref-first \
        --keep samples_subset.txt \
        --pred step1_test/step1_test_${PHENO_COLS}_pred.list \
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
        --chr "\${CHR}" \
        --out "step2_output/step2_test_chr\${CHR}" \
        --threads 8 \
        --gz

    rm -f "imp_test\${CHR}.pgen" "imp_test\${CHR}.pvar" "imp_test\${CHR}.psam"
done

# Remove inputs so SAK only auto-uploads outputs
rm -f test_array.bed test_array.bim test_array.fam samples_subset.txt pheno.tsv
rm -rf step1_test /tmp/regenie_tmp

echo "Test pipeline complete. Check logs for warnings."
JOBEOF
)

JOB2_ID=$(dx run app-swiss-army-knife \
    --instance-type "mem2_ssd2_v2_x16" \
    --priority normal \
    -icmd="${REGENIE_CMD}" \
    --name "regenie_test_regenie" \
    --destination "${OUTPUT_DIR}/test" \
    -y --brief)

echo "  Job 2 submitted: ${JOB2_ID}"
echo ""
echo "Monitor: dx watch ${JOB2_ID}"
echo "Results: ${OUTPUT_DIR}/test/"
