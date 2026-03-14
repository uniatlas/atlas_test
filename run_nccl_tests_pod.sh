#!/usr/bin/env bash
set -euo pipefail

# ====== 你可以改这些 ======
IB_HCAS=${IB_HCAS:-"ib7s400p0,ib7s400p1,ib7s400p2,ib7s400p3,ib7s400p4,ib7s400p5,ib7s400p6,ib7s400p7"}
SOCKET_IFNAMES=${SOCKET_IFNAMES:-"eth0"}
# 多机时在 hosts 文件里写每行一个 hostname 或 IP（例如：node1、node2）
HOSTFILE=${HOSTFILE:-"./hosts"}
#HOSTFILE=${HOSTFILE:-"/etc/mpi/hostfile"}
# 每台机器 GPU 数（也可以不设，自动用 nvidia-smi 统计）
GPUS_PER_NODE=${GPUS_PER_NODE:-""}

# 测试参数（可按需调整）
MIN_BYTES=${MIN_BYTES:-"8"}
MAX_BYTES=${MAX_BYTES:-"1G"}
STEP_FACTOR=${STEP_FACTOR:-"2"}
ITERS=${ITERS:-"100"}
WARMUP=${WARMUP:-"20"}
NGPUS_PER_PROC=${NGPUS_PER_PROC:-"1"}
LOG_ROOT=${LOG_ROOT:-"./nccl_logs"}
RUN_ID=${RUN_ID:-"$(date +%Y-%m-%d_%H%M%S)"}
#MPI_TCP_IF_INCLUDE=${MPI_TCP_IF_INCLUDE:-"bond0"}
MPI_TCP_IF_INCLUDE=${MPI_TCP_IF_INCLUDE:-"eth0"}

NCCL_TEST_BIN=./nccl-tests/build/all_reduce_perf_mpi

# NCCL 环境
export NCCL_DEBUG=${NCCL_DEBUG:-"INFO"}
export NCCL_DEBUG_SUBSYS=${NCCL_DEBUG_SUBSYS:-"NET"}
export NCCL_SOCKET_IFNAME=${NCCL_SOCKET_IFNAME:-"$SOCKET_IFNAMES"}
export NCCL_IB_HCA=${NCCL_IB_HCA:-"$IB_HCAS"}
# 如需强制走 IB/RDMA，可取消下一行注释
# export NCCL_IB_DISABLE=0

# ====== 准备 nccl-tests ======
if [ ! -d nccl-tests ]; then
  git clone https://github.com/NVIDIA/nccl-tests.git
fi

if [ ! -f nccl-tests/build/all_reduce_perf_mpi ]; then
  make MPI=1 -C nccl-tests -j"$(nproc)" CUDA_HOME=${CUDA_HOME:-/usr/local/cuda}
fi

# ====== 判断单机/多机 ======
if [ -f "$HOSTFILE" ]; then
  NNODES=$(grep -vE '^\s*#|^\s*$' "$HOSTFILE" | wc -l | tr -d ' ')
else
  NNODES=1
fi

CURRENT_HOSTS=$(hostname -s 2>/dev/null || true)
CURRENT_HOSTS+=" $(hostname 2>/dev/null || true) localhost 127.0.0.1"

check_local_ifnames_exist() {
  local csv=$1
  local missing=()
  local ifname

  IFS=',' read -r -a ifnames <<< "$csv"
  for ifname in "${ifnames[@]}"; do
    ifname=${ifname//[[:space:]]/}
    [ -n "$ifname" ] || continue
    if ! ip link show "$ifname" >/dev/null 2>&1; then
      missing+=("$ifname")
    fi
  done

  if [ "${#missing[@]}" -gt 0 ]; then
    echo "ERROR: NCCL socket interface(s) not found in this container: ${missing[*]}"
    echo "Hint: in pods, NCCL bootstrap usually needs the pod network interface, e.g.:"
    echo "  SOCKET_IFNAMES=eth0 ./run_nccl_tests_pod.sh"
    exit 1
  fi
}

check_local_ifnames_exist "$NCCL_SOCKET_IFNAME"

if [ -z "$GPUS_PER_NODE" ]; then
  if [ -n "${CUDA_VISIBLE_DEVICES:-}" ]; then
    GPUS_PER_NODE=$(awk -F',' '{print NF}' <<< "$CUDA_VISIBLE_DEVICES")
  elif command -v nvidia-smi >/dev/null 2>&1; then
    GPUS_PER_NODE=$(nvidia-smi -L 2>/dev/null | grep -c '^GPU ' || true)
  elif [ -d /proc/driver/nvidia/gpus ]; then
    GPUS_PER_NODE=$(find /proc/driver/nvidia/gpus -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
  else
    echo "ERROR: unable to auto-detect GPUs. Set GPUS_PER_NODE manually."
    exit 1
  fi
fi

if ! [[ "$GPUS_PER_NODE" =~ ^[0-9]+$ ]] || [ "$GPUS_PER_NODE" -le 0 ]; then
  echo "ERROR: GPUS_PER_NODE must be a positive integer, got '$GPUS_PER_NODE'."
  echo "Hint: verify GPU visibility in this environment, e.g.:"
  echo "  nvidia-smi -L"
  echo "  echo \"\$CUDA_VISIBLE_DEVICES\""
  echo "Or set GPUS_PER_NODE manually, e.g.:"
  echo "  GPUS_PER_NODE=8 ./run_nccl_tests.sh"
  exit 1
fi

NP=$((NNODES * GPUS_PER_NODE))
if [ "$NP" -le 0 ]; then
  echo "ERROR: total ranks NP must be > 0, got '$NP'."
  exit 1
fi
RUN_LOG_DIR="${LOG_ROOT}/${RUN_ID}"
MPI_OUTPUT_PREFIX="${RUN_LOG_DIR}/ranks"
COMBINED_LOG="${RUN_LOG_DIR}/combined.log"
SUMMARY_FILE="${RUN_LOG_DIR}/summary.txt"

mkdir -p "$RUN_LOG_DIR"

echo "==== NCCL test config ===="
echo "HOSTFILE      : $HOSTFILE (nodes=$NNODES)"
echo "GPUS_PER_NODE  : $GPUS_PER_NODE"
echo "NP (total ranks): $NP"
echo "NCCL_TEST_BIN  : $NCCL_TEST_BIN"
echo "RUN_LOG_DIR    : $RUN_LOG_DIR"
echo "MPI_TCP_IF_INCLUDE=$MPI_TCP_IF_INCLUDE"
echo "NCCL_SOCKET_IFNAME=$NCCL_SOCKET_IFNAME"
echo "NCCL_IB_HCA=$NCCL_IB_HCA"
echo "=========================="

print_perf_summary() {
  local log_file=$1
  local summary_file=$2

  summarize_one_size() {
    local target_bytes=$1
    local label=$2
    local line

    line=$(awk -v target="$target_bytes" '
      {
        start = index($0, target)
        if (start > 0) {
          line = substr($0, start)
          gsub(/[[:space:]]+/, " ", line)
          sub(/^ /, "", line)
          n = split(line, fields, " ")
          if (n >= 13 && fields[1] == target && fields[3] == "float" && fields[4] == "sum") {
            print line
          }
        }
      }
    ' "$log_file" | tail -n 1)

    if [ -z "$line" ]; then
      echo "  $label: not found"
      return
    fi

    echo "$line" | awk -v label="$label" '
      {
        n = split($0, fields, / +/)
        if (n < 13) {
          print "  " label ": " $0
          next
        }

        size = fields[1]
        out_time = fields[6]
        out_algbw = fields[7]
        out_busbw = fields[8]
        in_time = fields[10]
        in_algbw = fields[11]
        in_busbw = fields[12]

        printf("  %s: size=%s out_of_place(time=%sms algbw=%sGB/s busbw=%sGB/s) in_place(time=%sms algbw=%sGB/s busbw=%sGB/s)\n",
          label, size, out_time, out_algbw, out_busbw, in_time, in_algbw, in_busbw)
      }
    '
  }

  {
    echo
    echo "==== Key performance summary ===="
    summarize_one_size 536870912 "512MB"
    summarize_one_size 1073741824 "1GB"
    echo "==============================="
  } | tee "$summary_file"
}

# ====== 执行测试 ======
# 单机：直接 mpirun 不需要 hostfile
# 多机：需要你机器间免密 SSH + OpenMPI
MPI_ARGS=()
if [ "$NNODES" -gt 1 ]; then
  MPI_ARGS+=(--hostfile "$HOSTFILE")

  echo "Checking passwordless SSH to remote hosts..."
  while read -r host; do
    [ -n "$host" ] || continue
    case " $CURRENT_HOSTS " in
      *" $host "*)
        continue
        ;;
    esac

    if ! ssh -o BatchMode=yes -o ConnectTimeout=5 "$host" true >/dev/null 2>&1; then
      echo "ERROR: passwordless SSH check failed for host '$host'."
      echo "Hint: verify known_hosts / host key trust and SSH connectivity, e.g.:"
      echo "  ssh $host hostname"
      echo "  ssh-keyscan -H $host >> ~/.ssh/known_hosts"
      exit 1
    fi
  done < <(awk '!/^\s*#/ && NF {print $1}' "$HOSTFILE")
fi

# OpenMPI 默认禁止 root 运行；在容器/测试环境下可自动放行
MPI_ROOT_ARGS=()
if [ "$(id -u)" -eq 0 ]; then
  export OMPI_ALLOW_RUN_AS_ROOT=${OMPI_ALLOW_RUN_AS_ROOT:-1}
  export OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=${OMPI_ALLOW_RUN_AS_ROOT_CONFIRM:-1}
  MPI_ROOT_ARGS+=(--allow-run-as-root)
  echo "WARN: running mpirun as root (override enabled)."
fi

MPI_ENV_ARGS=(
  -x NCCL_DEBUG
  -x NCCL_DEBUG_SUBSYS
  -x NCCL_SOCKET_IFNAME
  -x NCCL_IB_HCA
)

if [ -n "${OMPI_ALLOW_RUN_AS_ROOT:-}" ]; then
  MPI_ENV_ARGS+=(-x OMPI_ALLOW_RUN_AS_ROOT)
fi

if [ -n "${OMPI_ALLOW_RUN_AS_ROOT_CONFIRM:-}" ]; then
  MPI_ENV_ARGS+=(-x OMPI_ALLOW_RUN_AS_ROOT_CONFIRM)
fi

if [ -n "${NCCL_IB_DISABLE:-}" ]; then
  MPI_ENV_ARGS+=(-x NCCL_IB_DISABLE)
fi

MPI_CMD=(
  mpirun
  -np "$NP"
  "${MPI_ROOT_ARGS[@]}"
  --tag-output
  --mca oob_tcp_if_include "$MPI_TCP_IF_INCLUDE"
  --mca btl_tcp_if_include "$MPI_TCP_IF_INCLUDE"
  --bind-to none --map-by "ppr:${GPUS_PER_NODE}:node"
  --output-filename "$MPI_OUTPUT_PREFIX"
  "${MPI_ENV_ARGS[@]}"
  "${MPI_ARGS[@]}"
  "$NCCL_TEST_BIN"
  -g "$NGPUS_PER_PROC"
  -b "$MIN_BYTES" -e "$MAX_BYTES" -f "$STEP_FACTOR"
  -w "$WARMUP" -i "$ITERS"
)

printf 'Running command: '
printf '%q ' "${MPI_CMD[@]}"
printf '\n'
echo "Combined log: $COMBINED_LOG"
echo "Summary log: $SUMMARY_FILE"
echo "Per-rank logs: ${MPI_OUTPUT_PREFIX}*"

"${MPI_CMD[@]}" 2>&1 | tee "$COMBINED_LOG"

print_perf_summary "$COMBINED_LOG" "$SUMMARY_FILE"
