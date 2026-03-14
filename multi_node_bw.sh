#!/bin/bash
# 用法: ./multi_node_bw.sh <本地节点IP> <远程节点IP>

LOCAL_IP=$1
# 每个节点配置 4 个进程，对应 4 个 IB 网卡
NUM_PROCS=4

echo "--- 准备进行 16 卡并行带宽测试 ---"

echo "在 $LOCAL_IP 启动服务端..."
for i in $(seq 0 $((NUM_PROCS-1))); do
    echo "ib_write_bw -d ib7s400p$i -s 134217728 -p $((10000+i)) -q 8  & "
    ib_write_bw -d ib7s400p$i -s 134217728 -p $((10000+i))  -R  &
done


