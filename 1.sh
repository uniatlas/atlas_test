#!/bin/bash
export NCCL_IB_IFNAME="ib7s400p0,ib7s400p1,ib7s400p2,ib7s400p3,ib7s400p4,ib7s400p5,ib7s400p6,ib7s400p7"

# 可选：强制开启 IB 验证，确保走 RDMA
export NCCL_IB_DISABLE=0 
export NCCL_NET_GDR_LEVEL=PHB # H100 通常建议设置为 PHB 或 PIX，具体取决于 NVLink 拓扑，默认自动通常最好


# --- MPI Root 权限覆盖 (必须同时设置这两个变量) ---
export OMPI_ALLOW_RUN_AS_ROOT=1
export OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1

# 运行测试
# -b 8: 起始数据量 8 Bytes
# -e 4G: 结束数据量 4 GB (H100 带宽高，建议测到大包)
# -f 2: 步长因子为 2 (8, 16, 32... 4G)
# -g 8: 使用 8 张 GPU (根据实际卡数调整)
# -n 100: 迭代次数，H100 速度快，可适当增加以获取稳定平均值
#./nccl-tests/build/all_reduce_perf -b 8 -e 4G -f 2 -g 8 -n 100
mpirun -np 8 \
  /data/liuqs/nccl-tests/build/all_reduce_perf_mpi \
  -b 8 -e 8G -f 2 -g 1
