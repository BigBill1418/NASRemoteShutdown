#!/bin/sh
# 03_task_scheduler_shutdown.sh
#
# DSM Task Scheduler script — run as root every 1 minute.
#
# WHY THIS EXISTS
# ---------------
# Synology patches sudo to always call PAM even for NOPASSWD commands.
# The PAM stack for sudo requires admin-group membership, which the
# restricted 'ha_shutdown' user intentionally lacks. pam_succeed_if.so
# (the standard bypass) is not present on Synology DSM.
#
# SOLUTION: ha_shutdown writes a flag file via SSH (no root needed).
# This root task sees the flag and calls synoshutdown directly.
#
# HOW TO INSTALL
# --------------
# In DSM: Control Panel → Task Scheduler → Create → Scheduled Task →
#         User-defined script
#   Task name : NAS Shutdown Flag Watcher
#   User      : root
#   Schedule  : Daily, repeat every 1 minute, all day
#   Task Settings → Run command: paste the script below
#
# SCRIPT (paste into Task Settings → Run command):
#
#   FLAG=/var/services/homes/ha_shutdown/.shutdown_requested
#   if [ -f "$FLAG" ]; then
#       rm -f "$FLAG"
#       /usr/syno/sbin/synoshutdown -s
#   fi

FLAG=/var/services/homes/ha_shutdown/.shutdown_requested

if [ -f "$FLAG" ]; then
    rm -f "$FLAG"
    /usr/syno/sbin/synoshutdown -s
fi
