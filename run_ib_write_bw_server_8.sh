#!/usr/bin/env bash
set -euo pipefail

MAP_FILE="${MAP_FILE:-./ib_map.csv}"

BASE_PORT=18515
DURATION=30
MSG_SIZE=65536
QPS=1
OUTDIR=${OUTDIR:-"./ib_write_bw_server_logs_$(date +%F_%H%M%S)"}

mkdir -p "$OUTDIR"

echo "[server] pwd=$(pwd)"
echo "[server] MAP_FILE=$MAP_FILE"
echo "[server] MAP_FILE(realpath)=$(realpath "$MAP_FILE")"
echo "[server] MAP_FILE(head):"
head -n 5 "$MAP_FILE"

idx=0
while IFS=',' read -r netdev rdma_dev rdma_port extra; do
  [[ -z "${netdev:-}" ]] && continue
  [[ "$netdev" =~ ^# ]] && continue

  # 强校验：防止读错文件/错格式
  if [[ -n "${extra:-}" ]]; then
    echo "ERROR: bad CSV (too many columns): $netdev,$rdma_dev,$rdma_port,$extra" >&2
    exit 1
  fi
  if [[ ! "$netdev" =~ ^ib7s400p[0-7]$ ]]; then
    echo "ERROR: bad netdev field '$netdev' (expected ib7s400p0..ib7s400p7). You are likely reading wrong file." >&2
    exit 1
  fi

  ctrl_port=$((BASE_PORT + idx))
  logfile="${OUTDIR}/server_${idx}_${netdev}_ctrl${ctrl_port}.log"

  nohup ib_write_bw \
    -d "$rdma_dev" \
    -p "$ctrl_port" \
    -D "$DURATION" \
    -s "$MSG_SIZE" \
    -q "$QPS" \
    --report_gbits \
    >"$logfile" 2>&1 &

  echo "[server] idx=$idx netdev=$netdev rdma_dev=$rdma_dev rdma_port=$rdma_port ctrl_port=$ctrl_port pid=$!"
  idx=$((idx + 1))
  [[ "$idx" -ge 8 ]] && break
done < "$MAP_FILE"

echo "[server] started $idx streams, logs=$OUTDIR"
wait
