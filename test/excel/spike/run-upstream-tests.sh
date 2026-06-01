#!/bin/bash
# Run upstream WRITE tests with to-blob transparently routed through :fast
# via the AGRAMMON_XLSX_FORCE_FAST env var honored inside _lib's to-blob.
#
# Usage: run-upstream-tests.sh <test-file> [<test-file> ...]
# Example:
#   ./test/excel/spike/run-upstream-tests.sh \
#       test/excel/spike/upstream-checkout/t/new-basic.rakutest
set -u
cd "$(dirname "$0")/../../.."   # repo root
export PERL5LIB=Inline/perl5
for t in "$@"; do
  echo "=== $t (via :fast) ==="
  AGRAMMON_XLSX_FORCE_FAST=1 raku -Itest/excel/spike/_lib -Itest/excel/spike -Itest/excel/spike/lib "$t"
  echo "=== exit=$? ==="
done
