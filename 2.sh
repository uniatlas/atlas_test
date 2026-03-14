#!/bin/bash
# --- 1. 加载 CUDA 12.8 环境 ---
export CUDA_HOME=/data/liuqs/cuda-12.8
export PATH=$CUDA_HOME/bin:$PATH
export LD_LIBRARY_PATH=$CUDA_HOME/lib64:$LD_LIBRARY_PATH

# 验证 CUDA 版本 (可选，调试用)
echo "Current CUDA Version:"
nvcc --version | grep release


# --- NCCL 配置 ---
export NCCL_IB_IFNAME="ib7s400p0,ib7s400p1,ib7s400p2,ib7s400p3,ib7s400p4,ib7s400p5,ib7s400p6,ib7s400p7"
export NCCL_IB_DISABLE=0
export NCCL_NET_GDR_LEVEL=PHB
export NCCL_SOCKET_IFNAME=eth0

# --- MPI Root 权限覆盖 (必须同时设置这两个变量) ---
export OMPI_ALLOW_RUN_AS_ROOT=1
export OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1
export GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
# --- 运行命令 ---
# 注意：多机测试时，-g 8 表示每个进程组(即每台机器)有8张卡
# -np 16 表示总共启动16个进程 (2台机器 x 8卡)
NNODES=$(wc -l < /etc/mpi/hostfile)
MASTER_ADDR=$(head -1 /etc/mpi/hostfile | cut -d' ' -f1)

# 自动获取以 ib7s 开头的设备名 (针对你的硬件环境)
HCA_LIST=$(ls /sys/class/infiniband | grep '^ib7s400' | tr '\n' ',' | sed 's/,$//')
echo "Detected IB HCAs: $HCA_LIST"

mpirun --allow-run-as-root \
    -np $NNODES \
    --hostfile /etc/mpi/hostfile \
    --map-by ppr:1:node \
    -mca plm_rsh_args "-i /tmp/.ssh/id_rsa -o StrictHostKeyChecking=no" \
    -x MASTER_ADDR=$MASTER_ADDR \
    -x MASTER_PORT=29503 \
    -x NCCL_DEBUG=INFO \
    -x NCCL_IB_DISABLE=0 \
    -x NCCL_IB_HCA="$HCA_LIST" \
    -x NCCL_IB_GID_INDEX=3 \
    -x NCCL_IB_CUDA_SUPPORT=1 \
    -x NCCL_NET_GDR_LEVEL=2 \
    -x NCCL_SOCKET_IFNAME=bond0,eth0 \
    bash -c 'echo "Hello from $(hostname), I am process"'
    

