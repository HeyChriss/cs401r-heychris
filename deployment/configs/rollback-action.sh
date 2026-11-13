#!/usr/bin/env bash
# Batch rollback. This path has no endpoint, so it does not call
# update-endpoint-weights-and-capacities. The action is to leave the
# candidate scores unpublished when ScoreDisagreementRate is above Threshold
# in deployment/configs/rollback-alarm.json.
#
# Usage, from the repo root:
#   bash deployment/configs/rollback-action.sh 0.706
set -euo pipefail
cd "$(dirname "$0")/../.."
RATE="${1:?pass the observed ScoreDisagreementRate, for example 0.706}"
THRESHOLD=$(sed -n 's/.*"Threshold": *\([0-9.][0-9.]*\).*/\1/p' deployment/configs/rollback-alarm.json | head -n 1)
[ -n "$THRESHOLD" ] || { echo "Threshold missing from deployment/configs/rollback-alarm.json"; exit 2; }
awk -v rate="$RATE" -v threshold="$THRESHOLD" 'BEGIN {
  printf "ScoreDisagreementRate %s  Threshold %s\n", rate, threshold
  if ((rate + 0) > (threshold + 0)) {
    print "ROLLBACK: do not publish the candidate batch output. The incumbent scores remain the production scores."
    exit 1
  }
  print "PROMOTE: disagreement rate is within the threshold."
}'
