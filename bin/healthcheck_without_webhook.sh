#!/usr/bin/env bash
# ==============================================================================
# Script Name: healthcheck.sh
# Description: 无 Agent 自动化运维巡检脚本 (SSH + Webhook)
# ==============================================================================
set -u

# --- 1. 全局环境与路径配置 ---
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOSTS_CONF="$BASE_DIR/conf/hosts.conf"
LOG_RETENTION_DAYS=7

if [ ! -f "$HOSTS_CONF" ]; then
    echo "$(date '+%F %T') ERROR: Config file $HOSTS_CONF not found!" >&2
    exit 1
fi

# --- 2. 告警阈值配置 ---
DISK_WARN=80
DISK_CRIT=90
LOAD_WARN_PER_CORE=0.7
LOAD_CRIT_PER_CORE=1.0

# --- 3. 核心工具函数 ---

ts() { date '+%F %T'; }

run_ssh() {
  local out rc
  out=$(timeout 5s ssh -n \
            -o BatchMode=yes \
            -o ConnectTimeout=5 \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -o LogLevel=ERROR \
            "$TARGET_HOST" "$@" )
  rc=$?
  if [ $rc -ne 0 ]; then return $rc; fi
  printf "%s" "$out"
}

# --- 4. 巡检主流程 ---
while read -r TARGET_HOST || [ -n "$TARGET_HOST" ]; do
  TARGET_HOST=$(echo "$TARGET_HOST" | tr -d '\r')
  [[ -z "$TARGET_HOST" || "$TARGET_HOST" =~ ^# ]] && continue

  LOCK_FILE="/tmp/healthcheck_${TARGET_HOST}.lock"
  LOG_DIR="$BASE_DIR/logs/$TARGET_HOST"
  DATE=$(date +%F)
  LOG_FILE="$LOG_DIR/$DATE.log"

  mkdir -p "$LOG_DIR"

  (
    if ! flock -n 9; then
      echo "$(ts) LOCKED: another instance for $TARGET_HOST is running" >> "$LOG_FILE"
      exit 0 
    fi

    STATUS_OK=0
    STATUS_WARN=1
    STATUS_CRIT=2
    STATUS_UNKNOWN=3
    overall=$STATUS_OK

    check_hostname=$STATUS_UNKNOWN
    check_load=$STATUS_UNKNOWN
    check_disk=$STATUS_UNKNOWN

    {
      echo "==== CHECK_TIME=$(ts) HOST=$TARGET_HOST ===="

      if ! HOSTNAME=$(run_ssh hostname); then
        echo "$(ts) CRITICAL: SSH connection failed for $TARGET_HOST"
        exit 0 
      else
        echo "HOSTNAME=$HOSTNAME"
        check_hostname=$STATUS_OK
      fi

      if CORES=$(run_ssh nproc); then
        echo "CORES=$CORES"
      else
        CORES=""
      fi

      if LOAD_1MIN=$(run_ssh uptime | awk -F'load average:' '{print $2}' | cut -d',' -f1 | xargs); then
        echo "LOAD_1MIN=$LOAD_1MIN"
        if [[ -n "${CORES:-}" && "$CORES" =~ ^[0-9]+$ ]]; then
          load_warn=$(awk -v c="$CORES" -v p="$LOAD_WARN_PER_CORE" 'BEGIN{printf "%.2f", c*p}')
          load_crit=$(awk -v c="$CORES" -v p="$LOAD_CRIT_PER_CORE" 'BEGIN{printf "%.2f", c*p}')
        else
          load_warn="1.00"
          load_crit="2.00"
        fi

        if awk -v l="$LOAD_1MIN" -v t="$load_crit" 'BEGIN{exit (l>=t)?0:1}'; then
          check_load=$STATUS_CRIT
          overall=$STATUS_CRIT
        elif awk -v l="$LOAD_1MIN" -v t="$load_warn" 'BEGIN{exit (l>=t)?0:1}'; then
          check_load=$STATUS_WARN
          (( overall < STATUS_WARN )) && overall=$STATUS_WARN
        else
          check_load=$STATUS_OK
        fi
      fi

      if DISK_ROOT_USED=$(run_ssh df -h / | awk 'NR==2 {print $5}'); then
        echo "DISK_ROOT_USED=$DISK_ROOT_USED"
        used_num=$(echo "$DISK_ROOT_USED" | tr -d '%' )
        if [[ "$used_num" =~ ^[0-9]+$ ]]; then
          if [ "$used_num" -ge "$DISK_CRIT" ]; then
            check_disk=$STATUS_CRIT
            overall=$STATUS_CRIT
          elif [ "$used_num" -ge "$DISK_WARN" ]; then
            check_disk=$STATUS_WARN
            (( overall < STATUS_WARN )) && overall=$STATUS_WARN
          else
            check_disk=$STATUS_OK
          fi
        fi
      fi

      case "$overall" in
        1) 
           alert_reason=""
           [ "$check_load" -eq "$STATUS_WARN" ] && alert_reason+="  - 负载偏高: $LOAD_1MIN\n"
           [ "$check_disk" -eq "$STATUS_WARN" ] && alert_reason+="  - 磁盘偏高: $DISK_ROOT_USED\n"
           echo "SUMMARY=WARN"
           ;;
        2) 
           alert_reason=""
           [ "$check_load" -eq "$STATUS_CRIT" ] && alert_reason+="  - 负载严重: $LOAD_1MIN\n"
           [ "$check_disk" -eq "$STATUS_CRIT" ] && alert_reason+="  - 磁盘严重: $DISK_ROOT_USED\n"
           echo "SUMMARY=CRIT"
           ;;
        0) echo "SUMMARY=OK" ;;
        *) echo "SUMMARY=UNKNOWN" ;;
      esac
      echo
    } >> "$LOG_FILE" 2>&1

    find "$LOG_DIR" -type f -name "*.log" -mtime +"$LOG_RETENTION_DAYS" -delete
  ) 9>"$LOCK_FILE"
done < "$HOSTS_CONF"
exit 0
