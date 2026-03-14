#!/bin/bash
# --- 1. 加载 CUDA 12.8 环境 ---
export CUDA_HOME=/data/liuqs/cuda-12.8
export PATH=$CUDA_HOME/bin:$PATH
export LD_LIBRARY_PATH=$CUDA_HOME/lib64:$LD_LIBRARY_PATH

# --- NCCL 配置 (关键修改在这里) ---
# 1. 强制禁用 CUDA Graphs (CUDA 12.x + 新驱动常见崩溃源)
export NCCL_CUDA_GRAPH_DISABLE=1

# 2. 强制禁用 P2P (Peer-to-Peer) 直接访问，改用拷贝模式 (排查 PCIe/NVLink 拓扑问题)
export NCCL_P2P_DISABLE=1

# 3. 如果上面两个还不行，尝试关闭 IB 的 GDR (GPU Direct RDMA) 测试一下是否稳定
# export NCCL_IB_GDR_LEVEL=0  <-- 先注释掉，前两个通常能解决

# 4. 保留你的 IB 设置 (如果前面测试过注释掉也没用，就写回来；如果不确定，先注释掉让系统自动选)
# export NCCL_IB_IFNAME="ib7s400p0,ib7s400p1,ib7s400p2,ib7s400p3,ib7s400p4,ib7s400p5,ib7s400p6,ib7s400p7"
export NCCL_IB_DISABLE=0
export NCCL_NET_GDR_LEVEL=PHB

# --- 调试信息 (必须加，看看到底停在哪) ---
export NCCL_DEBUG=INFO
export CUDA_LAUNCH_BLOCKING=1

# --- MPI Root 权限 ---
export OMPI_ALLOW_RUN_AS_ROOT=1
export OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1

# --- 运行命令 (建议先单机测试，把 -np 16 改为 -np 8，去掉 --hostfile) ---
# 强烈建议先单机跑通，再跑多机！
mpirun -np 8 ./nccl-tests/build/all_reduce_perf -b 8 -e 4G -f 2 -g 8 -n 100
