#!/bin/bash

# Script to enable, disable, or check the status of NUMA balancing
# Usage:
#   sudo ./numa_balancing.sh enable
#   sudo ./numa_balancing.sh disable
#   ./numa_balancing.sh status

PARAM="kernel.numa_balancing"

if [[ "$EUID" -ne 0 && "$1" != "status" ]]; then
  echo "[ERROR] Please run as root for enable/disable actions."
  exit 1
fi

case "$1" in
  enable)
    sysctl -w $PARAM=1 >/dev/null
    echo "[INFO] NUMA balancing ENABLED."
    ;;
  disable)
    sysctl -w $PARAM=0 >/dev/null
    echo "[INFO] NUMA balancing DISABLED."
    ;;
  status)
    current=$(sysctl -n $PARAM)
    if [[ "$current" -eq 1 ]]; then
      echo "[STATUS] NUMA balancing is ENABLED."
    else
      echo "[STATUS] NUMA balancing is DISABLED."
    fi
    ;;
  *)
    echo "Usage: $0 [enable|disable|status]"
    exit 1
    ;;
esac
