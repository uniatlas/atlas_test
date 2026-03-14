#!/usr/bin/env bash
set -euo pipefail

# ====== 你可以改这些 ======
IFNAMES=${IFNAMES:-"ib7s400p0,ib7s400p1,ib7s400p2,ib7s400p3,ib7s400p4,ib7s400p5,ib7s400p6,ib7s400p7"}
# 多机时在 hosts 文件里写每行一个 hostname 或 IP（例如：node1、node2）
HOSTFILE=${HOSTFILE:-"./hosts"}
# 每台机器 GPU 数（也可以不设，自动用 nvidia-smi 统计）
GPUS_PER_NODE=${GPUS_PER_NODE:-""}

# 测试参数（可按需调整）
MIN_BYTES=${MIN_BYTES:-"8"}
MAX_BYTES=${MAX_BYTES:-"1G"}
STEP_FACTOR=${STEP_FACTOR:-"2"}
ITERS=${ITERS:-"100"}
WARMUP=${WARMUP:-"20"}

# NCCL 环境
export NCCL_DEBUG=${NCCL_DEBUG:-"WARN"}
export NCCL_DEBUG_SUBSYS=${NCCL_DEBUG_SUBSYS:-"NET,INIT,ENV"}
export NCCL_SOCKET_IFNAME=${NCCL_SOCKET_IFNAME:-"$IFNAMES"}

# 如需强制走 IB/RDMA，可取消下一行注释
export NCCL_IB_DISABLE=0

# ====== 准备 nccl-tests ======
if [ ! -d nccl-tests ]; then
  git clone https://github.com/NVIDIA/nccl-tests.git
fi

if [ ! -f nccl-tests/build/all_reduce_perf ]; then
  make MPI=1 -C nccl-tests -j"$(nproc)" CUDA_HOME=${CUDA_HOME:-/usr/local/cuda}
fi

# ====== 判断单机/多机 ======
if [ -f "$HOSTFILE" ]; then
  NNODES=$(grep -vE '^\s*#|^\s*$' "$HOSTFILE" | wc -l | tr -d ' ')
else
  NNODES=1
fi

if [ -z "$GPUS_PER_NODE" ]; then
  if command -v nvidia-smi >/dev/null 2>&1; then
    GPUS_PER_NODE=$(nvidia-smi -L | wc -l | tr -d ' ')
  else
    echo "ERROR: nvidia-smi not found; set GPUS_PER_NODE manually."
    exit 1
  fi
fi

NP=$((NNODES * GPUS_PER_NODE))

echo "==== NCCL test config ===="
echo "HOSTFILE      : $HOSTFILE (nodes=$NNODES)"
echo "GPUS_PER_NODE  : $GPUS_PER_NODE"
echo "NP (total ranks): $NP"
echo "NCCL_SOCKET_IFNAME=$NCCL_SOCKET_IFNAME"
echo "=========================="

# ====== 执行测试 ======
# 单机：直接 mpirun 不需要 hostfile
# 多机：需要你机器间免密 SSH + OpenMPI
MPI_ARGS=()
if [ "$NNODES" -gt 1 ]; then
  MPI_ARGS+=(--hostfile "$HOSTFILE")
fi

# OpenMPI 默认禁止 root 运行；在容器/测试环境下可自动放行
MPI_ROOT_ARGS=()
if [ "$(id -u)" -eq 0 ]; then
  export OMPI_ALLOW_RUN_AS_ROOT=${OMPI_ALLOW_RUN_AS_ROOT:-1}
  export OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=${OMPI_ALLOW_RUN_AS_ROOT_CONFIRM:-1}
  MPI_ROOT_ARGS+=(--allow-run-as-root)
  echo "WARN: running mpirun as root (override enabled)."
fi

mpirun -np "$NP" \
  "${MPI_ROOT_ARGS[@]}" \
  --bind-to none --map-by ppr:${GPUS_PER_NODE}:node \
  -x NCCL_DEBUG -x NCCL_DEBUG_SUBSYS -x NCCL_SOCKET_IFNAME \
  -x OMPI_ALLOW_RUN_AS_ROOT -x OMPI_ALLOW_RUN_AS_ROOT_CONFIRM \
  -x NCCL_IB_DISABLE \
  "${MPI_ARGS[@]}" \
  ./nccl-tests/build/all_reduce_perf \
    -b "$MIN_BYTES" -e "$MAX_BYTES" -f "$STEP_FACTOR" \
    -w "$WARMUP" -i "$ITERS"
