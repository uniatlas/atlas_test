#!/usr/bin/env bash
set -euo pipefail

NETDEVS=(ib7s400p0 ib7s400p1 ib7s400p2 ib7s400p3 ib7s400p4 ib7s400p5 ib7s400p6 ib7s400p7)

echo "# netdev,rdma_dev,rdma_port"
for nd in "${NETDEVS[@]}"; do
  if [[ ! -e "/sys/class/net/$nd" ]]; then
    echo "# WARN: $nd not found" >&2
    continue
  fi

  devpath="$(readlink -f /sys/class/net/$nd/device)"
  rdma_dev="$(ls -1 "$devpath/infiniband" 2>/dev/null | head -n 1 || true)"
  if [[ -z "${rdma_dev}" ]]; then
    echo "# WARN: cannot find RDMA dev for $nd (no $devpath/infiniband)" >&2
    continue
  fi

  rdma_port=""
  for p in "$devpath/infiniband/$rdma_dev/ports/"*; do
    [[ -d "$p" ]] || continue
    portnum="$(basename "$p")"

    # 常见路径：ports/<n>/gid_attrs/ndevs/<gid_index> 文件内容是 netdev
    if [[ -d "$p/gid_attrs/ndevs" ]] && grep -Rqsx "$nd" "$p/gid_attrs/ndevs" 2>/dev/null; then
      rdma_port="$portnum"
      break
    fi
    # 有些系统是目录里直接出现同名条目
    if [[ -d "$p/gid_attrs/ndevs" ]] && ls -1 "$p/gid_attrs/ndevs" 2>/dev/null | grep -qx "$nd"; then
      rdma_port="$portnum"
      break
    fi
  done

  if [[ -z "${rdma_port}" ]]; then
    echo "# WARN: cannot map port for $nd, fallback port=1" >&2
    rdma_port="1"
  fi

  echo "${nd},${rdma_dev},${rdma_port}"
done
