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

# --- MPI Root 权限覆盖 (必须同时设置这两个变量) ---
export OMPI_ALLOW_RUN_AS_ROOT=1
export OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1

# --- 运行命令 ---
# 注意：多机测试时，-g 8 表示每个进程组(即每台机器)有8张卡
# -np 16 表示总共启动16个进程 (2台机器 x 8卡)
#mpirun --hostfile hosts -np 16 ./nccl-tests/build/all_reduce_perf_mpi -b 8 -e 4G -f 2 -g 8 -n 100
NNODES=$(wc -l < /etc/mpi/hostfile)
MASTER_ADDR=$(head -1 /etc/mpi/hostfile | cut -d' ' -f1)
#mpirun --mca routed direct \
#       --hostfile /etc/mpi/hostfile \
#       -np $NNODES \
#       --map-by ppr:1:node \
#       ./nccl-tests/build/all_reduce_perf_mpi -b 8 -e 4G -f 2 -g 8 -n 100


mpirun --mca routed direct \
       --hostfile /etc/mpi/hostfile \
       -np $NNODES \
       --map-by ppr:1:node \
       ./nccl-tests/build/all_reduce_perf_mpi -b 8 -e 4G -f 2 -g 8 -n 100
       #bash -c 'echo "Hello from $(hostname), I am process $OMPI_COMM_WORLD_RANK"'



