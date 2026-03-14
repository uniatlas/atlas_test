#!/usr/bin/env bash
set -euo pipefail

DEVS=(ib7s400p0 ib7s400p1 ib7s400p2 ib7s400p3 ib7s400p4 ib7s400p5 ib7s400p6 ib7s400p7)
BASE_PORT=18515
DURATION=30
MSG_SIZE=65536
QPS=1
OUTDIR=${OUTDIR:-"./ib_write_bw_server_logs_$(date +%F_%H%M%S)"}

mkdir -p "$OUTDIR"

for idx in "${!DEVS[@]}"; do
  dev="${DEVS[$idx]}"
  ctrl_port=$((BASE_PORT + idx))
  logfile="${OUTDIR}/server_${idx}_${dev}_ctrl${ctrl_port}.log"

  numa_node="$(cat /sys/class/net/$dev/device/numa_node 2>/dev/null || echo -1)"
  numa_prefix=()
  if [[ "$numa_node" != "-1" ]] && command -v numactl >/dev/null 2>&1; then
    numa_prefix=(numactl -N "$numa_node" -m "$numa_node")
  fi

  echo "[server] idx=$idx dev=$dev numa=$numa_node ctrl_port=$ctrl_port"
  nohup "${numa_prefix[@]}" ib_write_bw \
    -d "$dev" \
    -p "$ctrl_port" \
    -D "$DURATION" \
    -s "$MSG_SIZE" \
    -q "$QPS" \
    --report_gbits \
    >"$logfile" 2>&1 &
done

echo "[server] logs=$OUTDIR"
wait
