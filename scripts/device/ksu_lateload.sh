#!/system/bin/sh
# 通过常驻 root FIFO 通道执行的 KernelSU 晚加载脚本。
#
# 运行上下文：uid=0，u:r:kernel:s0，SELinux Permissive。
# 由 chain_hook.sh 建立的 /data/local/tmp/rs.in 通道投递执行。
#
# 为什么不用 load_ko + fake kallsyms：
#   本机实测静态符号表（fne_syms.txt）与运行内核大面积不一致 ——
#   57154 个符号差 0x30、41699 个差 0x180；更致命的是厂商已把
#   commit_creds / prepare_kernel_cred 从 kallsyms 中过滤掉，手工补出的
#   地址是错的，模块 init 一跳就飞（panic）。
#   官方 ksud（3.3.0）的 insmod 子命令自带运行时符号解析与重定位，
#   不需要任何手工地址表，因此改用 ksud insmod。

D=/data/local/tmp/ksu_fne
export PATH=/system/bin:/data/local/tmp/ksu_fne:$PATH

echo "=== KSU late-load start $(date) ==="
echo "uid=$(id -u) enforce=$(getenforce) ctx=$(cat /proc/self/attr/current 2>/dev/null)"

# 1) 让 insmod 期间的任何 oops 变成可观察日志，而不是直接重启
po=$(cat /proc/sys/kernel/panic_on_oops 2>/dev/null); echo "panic_on_oops=$po -> 0"
echo 0 > /proc/sys/kernel/panic_on_oops
echo 0 > /proc/sys/kernel/kptr_restrict

# 2) 快照原始 SELinux 策略（供模块的 selinux_hide 备份使用）
[ -s $D/pristine_policy ] || cat /sys/fs/selinux/policy > $D/pristine_policy
echo "pristine_policy: $(wc -c < $D/pristine_policy 2>/dev/null) bytes"

# 3) 先注入 ksu 域所需的 SELinux 规则（late-load 不会自己应用规则，
#    规则必须预先存在，否则模块加载后在 enforce 切换时会废掉）
$D/magiskpolicy --apply $D/ksu_rules --live >/dev/null 2>&1
echo "magiskpolicy rc=$?"

# 4) 官方 ksud insmod
echo "--- ksud insmod ---"
$D/ksud insmod $D/kernelsu.ko "allow_shell=1 pristine_policy=$D/pristine_policy" 2>&1
echo "ksud insmod rc=$?"
sleep 3

# 5) 收尾检查：模块是否真的 Live、su 入口是否装好
echo "--- /proc/modules ---"
grep kernelsu /proc/modules 2>&1
echo "--- su 入口 ---"
ls -l /system/bin/su 2>&1
echo "--- su 自检 ---"
/system/bin/su -c id 2>&1
echo "KSUTRY_DONE"
