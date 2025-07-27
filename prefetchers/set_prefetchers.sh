#!/bin/bash

# Usage:
#   sudo ./set_prefetchers.sh disable all
#   sudo ./set_prefetchers.sh enable all
#   sudo ./set_prefetchers.sh disable 0x5
#   sudo ./set_prefetchers.sh enable 0x0
#   sudo ./set_prefetchers.sh status

modprobe msr

if [[ "$EUID" -ne 0 ]]; then
  echo "[ERROR] Please run as root"
  exit 1
fi

ACTION="$1"
MODE="$2"

MSR=0x1A4

print_status() {
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  NC='\033[0m'  # No Color

  echo -e "\n[INFO] Current Prefetcher Status per Core:"
  echo "Bitmask: 0x1A4 — [0]HW [1]Adjacent [2]DCU [3]IP"
  printf "%-6s %-6s %-12s %-12s %-12s %-12s\n" "Core" "Mask" "HW" "ADJ" "DCU" "IP"

  for cpu in /dev/cpu/[0-9]*; do
    core=$(basename "$cpu")
    hex_value=$(rdmsr -p "$core" 0x1A4 2>/dev/null)

    if [[ $? -ne 0 ]]; then
      printf "%-6s %-6s %-12s %-12s %-12s %-12s\n" "$core" "ERROR" "-" "-" "-" "-"
      continue
    fi

    dec_value=$((0x$hex_value))

    hw_bit=$(( (dec_value >> 0) & 1 ))
    adj_bit=$(( (dec_value >> 1) & 1 ))
    dcu_bit=$(( (dec_value >> 2) & 1 ))
    ip_bit=$(( (dec_value >> 3) & 1 ))

    # Use raw strings for accurate alignment
    hw_status=$([[ $hw_bit -eq 1 ]] && echo -e "${RED}DIS${NC} ($hw_bit)" || echo -e "${GREEN}EN${NC}  ($hw_bit)")
    adj_status=$([[ $adj_bit -eq 1 ]] && echo -e "${RED}DIS${NC} ($adj_bit)" || echo -e "${GREEN}EN${NC}  ($adj_bit)")
    dcu_status=$([[ $dcu_bit -eq 1 ]] && echo -e "${RED}DIS${NC} ($dcu_bit)" || echo -e "${GREEN}EN${NC}  ($dcu_bit)")
    ip_status=$([[ $ip_bit -eq 1 ]] && echo -e "${RED}DIS${NC} ($ip_bit)" || echo -e "${GREEN}EN${NC}  ($ip_bit)")

    printf "%-6s 0x%-4X %-12b %-12b %-12b %-12b\n" \
      "$core" "$dec_value" "$hw_status" "$adj_status" "$dcu_status" "$ip_status"
  done
  echo ""
}

if [[ "$ACTION" == "status" ]]; then
  print_status
  exit 0
elif [[ "$ACTION" != "disable" && "$ACTION" != "enable" ]]; then
  echo "Usage: $0 [disable|enable|status] [all|bitmask]"
  exit 1
fi

if [[ "$MODE" == "all" ]]; then
  if [[ "$ACTION" == "disable" ]]; then
    MASK=0xF  # Disable all prefetchers
  else
    MASK=0x0  # Enable all prefetchers
  fi
else
  MASK="$MODE"
fi

echo "[INFO] Setting MSR $MSR to $MASK on all cores..."

for cpu in /dev/cpu/[0-9]*; do
  core=$(basename "$cpu")
  wrmsr -p "$core" $MSR "$MASK"
  echo " -> Core $core updated"
done
