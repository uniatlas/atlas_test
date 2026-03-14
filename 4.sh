#!/bin/bash
set -e

# --- 1. 加载 CUDA 12.8 环境 ---
export CUDA_HOME=/data/liuqs/cuda-12.8
export PATH=$CUDA_HOME/bin:$PATH
export LD_LIBRARY_PATH=$CUDA_HOME/lib64:$LD_LIBRARY_PATH

echo "Current CUDA Version:"
nvcc --version | grep release || echo "Warning: nvcc not found or version check failed"

# --- 2. NCCL 核心配置 (关键修复) ---
# 数据通道：使用 IB
export NCCL_IB_IFNAME="ib7s400p0,ib7s400p1,ib7s400p2,ib7s400p3,ib7s400p4,ib7s400p5,ib7s400p6,ib7s400p7"
export NCCL_IB_DISABLE=0
export NCCL_NET_GDR_LEVEL=PHB

# 控制通道：强制使用 eth0 (防止 NCCL 自动选择错误的接口)
export NCCL_SOCKET_IFNAME=eth0

# 【新增】调试日志：出错时能看到详细原因
export NCCL_DEBUG=INFO
export NCCL_DEBUG_SUBSYS=NET,INIT,ENV

# 【新增】超时设置：防止因网络慢直接挂掉，给多一点时间 (秒)
export NCCL_TIMEOUT=3600

# --- 3. MPI 配置 ---
export OMPI_ALLOW_RUN_AS_ROOT=1
export OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1

# 消除 SSH 警告 (可选)
export GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

echo "=========================================="
echo "Starting NCCL Test with 16 processes..."
echo "IB Interfaces: $NCCL_IB_IFNAME"
echo "Socket Interface: $NCCL_SOCKET_IFNAME"
echo "=========================================="

# --- 4. 运行命令 ---
# 注意：-x 必须包含所有上面设置的 NCCL 变量，确保远程节点也能拿到相同的配置
mpirun --mca routed direct \
       --mca oob_tcp_if_include eth0 \
       --mca btl_tcp_if_include eth0 \
       --hostfile /etc/mpi/hostfile \
       -np 16 \
       --bind-to none \
       --map-by ppr:8:node \
       -x NCCL_IB_IFNAME \
       -x NCCL_IB_DISABLE \
       -x NCCL_NET_GDR_LEVEL \
       -x NCCL_SOCKET_IFNAME \
       -x NCCL_DEBUG \
       -x NCCL_DEBUG_SUBSYS \
       -x NCCL_TIMEOUT \
       -x PATH \
       -x LD_LIBRARY_PATH \
       -x CUDA_HOME \
       ./nccl-tests/build/all_reduce_perf_mpi \
       -b 8 -e 4G -f 2 -g 1 -n 100
