#!/system/bin/sh
# 最后一步：把 SELinux 从 Permissive 切回 Enforcing。
#
# 注意：本脚本由 u:r:kernel:s0 的 root 通道 shell 执行，切换 enforcing 会
# 杀掉所有 kernel:s0 进程（包括执行它的这个 shell 自己），所以它是整个流程
# 的最后一条命令 —— 上面所有工作都已落盘。
#
# 切换后 root 依然可用：/system/bin/su 走的是 KernelSU 的 u:r:ksu:s0 域，
# 不再依赖 kernel 上下文，也不再依赖 Permissive。

echo "before: enforce=$(getenforce)"
echo 1 > /sys/fs/selinux/enforce 2>&1
sleep 1
echo "after: enforce=$(getenforce)"
echo "RESTORE_ENFORCE_DONE"
