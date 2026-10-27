#!/usr/bin/env bash
# รีเซ็ต AnyDesk ID ใหม่ (ลบ identity เดิมใน /etc/anydesk แล้วให้ service ขอ ID ใหม่จาก server)
# ติดตั้งเป็นไอคอนในรายการ app : bash renew-anydesk-id.sh --install   (sudo = ติดตั้งให้ทุก user)
# ถอนการติดตั้ง               : bash renew-anydesk-id.sh --uninstall
# ใช้ผ่าน terminal / SSH        : sudo anydesk-renew-id --cli
set -euo pipefail

APP_ID="anydesk-renew-id"
APP_NAME="Renew AnyDesk ID"
CONF_DIR="/etc/anydesk"
BACKUP_ROOT="/var/backups/anydesk-renew-id"
LOG_FILE="/var/log/anydesk-renew-id.log"
SELF="$(readlink -f "${BASH_SOURCE[0]}")"

# ---------- ส่วนที่รันเป็น root ----------

# GUI mode ส่งบรรทัดให้ zenity --progress, CLI mode พิมพ์ข้อความปกติ
OUT_MODE="cli"
step() {
  if [[ "$OUT_MODE" == "gui" ]]; then
    printf '%s\n# %s\n' "$1" "$2"
  else
    printf '[%3s%%] %s\n' "$1" "$2"
  fi
}

get_id() {
  local id
  id="$(timeout 5 anydesk --get-id 2>/dev/null | tr -dc '0-9' || true)"
  [[ -n "$id" && "$id" != "0" ]] && echo "$id"
  return 0
}

stop_anydesk() {
  systemctl stop anydesk 2>/dev/null || true
  pkill -x anydesk 2>/dev/null || true
  for _ in $(seq 1 10); do
    pgrep -x anydesk >/dev/null || return 0
    sleep 1
  done
  pkill -9 -x anydesk 2>/dev/null || true
  sleep 1
}

# รับรหัส Unattended Access ทาง stdin บรรทัดแรก (ว่าง = ไม่ตั้ง)
do_reset() {
  OUT_MODE="${1:-cli}"
  local pw="" old_id new_id ts backup f home
  IFS= read -r pw || true

  if (( EUID != 0 )); then
    echo "ERROR=ต้องรันด้วยสิทธิ์ root" ; return 1
  fi
  if ! command -v anydesk >/dev/null; then
    echo "ERROR=ไม่พบโปรแกรม AnyDesk ในเครื่อง" ; return 1
  fi

  step 5 "อ่าน ID เดิม..."
  old_id="$(get_id)"

  step 15 "สำรองไฟล์ตั้งค่าเดิม..."
  ts="$(date +%Y%m%d-%H%M%S)"
  backup="$BACKUP_ROOT/$ts"
  install -d -m 0700 "$backup"
  for f in "$CONF_DIR/service.conf" "$CONF_DIR/system.conf" "$CONF_DIR/.iid"; do
    [[ -e "$f" ]] && cp -a "$f" "$backup/"
  done
  # AnyDesk รุ่นเก่าเก็บ identity ไว้ใน home ด้วย
  for home in /root /home/*; do
    for f in "$home/.anydesk/service.conf" "$home/.anydesk/system.conf"; do
      if [[ -e "$f" ]]; then
        install -d -m 0700 "$backup/home/$(basename "$home")"
        cp -a "$f" "$backup/home/$(basename "$home")/"
      fi
    done
  done

  step 30 "หยุด AnyDesk service..."
  stop_anydesk

  step 45 "ลบ ID เดิม..."
  rm -f "$CONF_DIR/service.conf" "$CONF_DIR/system.conf" "$CONF_DIR/.iid"
  for home in /root /home/*; do
    rm -f "$home/.anydesk/service.conf" "$home/.anydesk/system.conf"
  done

  step 55 "เปิด AnyDesk service ใหม่..."
  systemctl start anydesk

  step 65 "รอรับ ID ใหม่จาก AnyDesk server..."
  new_id=""
  for _ in $(seq 1 90); do
    new_id="$(get_id)"
    [[ -n "$new_id" ]] && break
    sleep 1
  done
  if [[ -z "$new_id" ]]; then
    echo "$(date '+%F %T') FAIL old=${old_id:-?} backup=$backup" >>"$LOG_FILE"
    echo "ERROR=ไม่ได้รับ ID ใหม่ภายใน 90 วินาที (ตรวจสอบอินเทอร์เน็ต) ไฟล์เดิมสำรองไว้ที่ $backup"
    return 1
  fi

  if [[ -n "$pw" ]]; then
    step 85 "ตั้งรหัส Unattended Access..."
    if ! printf '%s\n' "$pw" | anydesk --set-password >/dev/null 2>&1; then
      echo "PWFAIL=1"
    fi
  fi
  pw=""

  echo "$(date '+%F %T') OK old=${old_id:-?} new=$new_id backup=$backup" >>"$LOG_FILE"
  echo "OLDID=${old_id:-}"
  echo "NEWID=$new_id"
  echo "BACKUP=$backup"
  step 100 "เสร็จสิ้น"
}

# ---------- ติดตั้ง / ถอนการติดตั้ง ----------

paths() {
  if (( EUID == 0 )); then
    BIN_PATH="/usr/local/bin/$APP_ID"
    DESKTOP_PATH="/usr/share/applications/$APP_ID.desktop"
  else
    BIN_PATH="$HOME/.local/bin/$APP_ID"
    DESKTOP_PATH="$HOME/.local/share/applications/$APP_ID.desktop"
  fi
}

do_install() {
  paths
  install -D -m 0755 "$SELF" "$BIN_PATH"
  install -d "$(dirname "$DESKTOP_PATH")"
  cat >"$DESKTOP_PATH" <<EOF
[Desktop Entry]
Type=Application
Name=$APP_NAME
Name[th]=รีเซ็ต AnyDesk ID ใหม่
GenericName=AnyDesk ID Reset
Comment=Reset this computer's AnyDesk ID to a new one
Comment[th]=ล้าง AnyDesk ID เดิมแล้วขอ ID ใหม่
Exec=$BIN_PATH
Icon=anydesk
Terminal=false
Categories=Network;RemoteAccess;
Keywords=anydesk;id;reset;renew;remote;
StartupNotify=true
EOF
  chmod 0644 "$DESKTOP_PATH"
  update-desktop-database "$(dirname "$DESKTOP_PATH")" 2>/dev/null || true
  echo "ติดตั้งแล้ว:"
  echo "  โปรแกรม : $BIN_PATH"
  echo "  ไอคอน   : $DESKTOP_PATH"
  echo "เปิดได้จากรายการ app โดยค้นหา \"AnyDesk\" หรือ \"$APP_NAME\""

  local cmd missing=()
  for cmd in anydesk zenity pkexec; do
    command -v "$cmd" >/dev/null || missing+=("$cmd")
  done
  if (( ${#missing[@]} )); then
    echo "คำเตือน: ยังไม่มี ${missing[*]} ในเครื่อง"
    echo "  AnyDesk ติดตั้งจาก https://anydesk.com หรือ apt repo ของ AnyDesk"
    echo "  ที่เหลือ: sudo apt install zenity pkexec xclip"
  fi
}

do_uninstall() {
  paths
  rm -f "$BIN_PATH" "$DESKTOP_PATH"
  update-desktop-database "$(dirname "$DESKTOP_PATH")" 2>/dev/null || true
  echo "ถอนการติดตั้งแล้ว"
}

# ---------- หน้าต่าง GUI (รันเป็น user ปกติ) ----------

zerr() { zenity --error --title="$APP_NAME" --width=420 --text="$1" 2>/dev/null || true; }

run_gui() {
  local old_id pw1 pw2 form out rc new_id backup err

  if ! command -v anydesk >/dev/null; then
    zerr "ไม่พบโปรแกรม AnyDesk ในเครื่องนี้"; exit 1
  fi
  old_id="$(get_id)"

  zenity --question --title="$APP_NAME" --width=460 \
    --icon=anydesk --ok-label="รีเซ็ต ID" --cancel-label="ยกเลิก" \
    --text="<big><b>รีเซ็ต AnyDesk ID ใหม่</b></big>

ID ปัจจุบัน: <b>${old_id:-ไม่ทราบ}</b>

• ทุกคนที่กำลัง remote เข้าเครื่องนี้ผ่าน AnyDesk <b>จะหลุดทันที</b>
• ต้องใช้ ID ใหม่ในการเชื่อมต่อครั้งต่อไป
• รหัส Unattended Access เดิมจะหาย (ตั้งใหม่ได้ในขั้นถัดไป)
• ไฟล์ตั้งค่าเดิมจะสำรองไว้ที่ $BACKUP_ROOT

ต้องการดำเนินการต่อหรือไม่?" 2>/dev/null || exit 0

  # ขอรหัส Unattended Access ใหม่ (เว้นว่าง = ไม่ตั้ง)
  pw1=""
  while true; do
    form="$(zenity --forms --title="$APP_NAME" --width=420 \
      --text="ตั้งรหัส Unattended Access ใหม่ (อย่างน้อย 8 ตัวอักษร)
เว้นว่างทั้งสองช่องถ้าไม่ต้องการตั้งรหัส" \
      --add-password="รหัสผ่าน" --add-password="ยืนยันรหัสผ่าน" \
      --separator=$'\x1f' --ok-label="ถัดไป" --cancel-label="ยกเลิก" 2>/dev/null)" || exit 0
    pw1="${form%%$'\x1f'*}"
    pw2="${form#*$'\x1f'}"
    if [[ "$pw1" != "$pw2" ]]; then zerr "รหัสผ่านทั้งสองช่องไม่ตรงกัน"; continue; fi
    if [[ -n "$pw1" ]] && (( ${#pw1} < 8 )); then zerr "รหัสผ่านต้องมีอย่างน้อย 8 ตัวอักษร"; continue; fi
    break
  done
  unset form pw2

  # pkexec จะเด้งหน้าต่างขอรหัส admin ของเครื่อง แล้วรันส่วน reset เป็น root
  out="$(mktemp)"
  trap "rm -f -- '$out'" EXIT
  set +e
  printf '%s\n' "$pw1" | pkexec "$SELF" --reset gui 2>/dev/null | tee "$out" |
    zenity --progress --title="$APP_NAME" --width=420 --text="กำลังเริ่ม..." \
      --percentage=0 --auto-close --no-cancel 2>/dev/null
  rc=${PIPESTATUS[1]}
  set -e
  unset pw1

  if (( rc == 126 || rc == 127 )) && [[ ! -s "$out" ]]; then
    zerr "ยกเลิก หรือใส่รหัส admin ไม่ถูกต้อง — ยังไม่มีการเปลี่ยนแปลงใด ๆ"; exit 1
  fi
  err="$(sed -n 's/^ERROR=//p' "$out")"
  new_id="$(sed -n 's/^NEWID=//p' "$out")"
  backup="$(sed -n 's/^BACKUP=//p' "$out")"
  if [[ -n "$err" || -z "$new_id" ]]; then
    zerr "รีเซ็ตไม่สำเร็จ
${err:-ไม่ทราบสาเหตุ (exit $rc)}"; exit 1
  fi

  local note=""
  [[ "$new_id" == "$old_id" ]] && note="

⚠ ได้ ID เดิมกลับมา — AnyDesk server อาจจำเครื่องนี้ไว้"
  grep -q '^PWFAIL=1' "$out" && note+="

⚠ ตั้งรหัส Unattended Access ไม่สำเร็จ — ตั้งเองได้ในหน้าตั้งค่า AnyDesk"

  notify-send -i anydesk "$APP_NAME" "AnyDesk ID ใหม่: $new_id" 2>/dev/null || true

  # ปุ่ม extra จะพิมพ์ชื่อปุ่มออก stdout แล้ว exit 1
  local copy_label="คัดลอก ID" choice
  choice="$(zenity --info --title="$APP_NAME" --width=420 --icon=anydesk \
    --ok-label="ปิด" --extra-button="$copy_label" \
    --text="<big>AnyDesk ID ใหม่</big>

<span size='xx-large' weight='bold'>$new_id</span>

ID เดิม: ${old_id:-ไม่ทราบ}
สำรองไฟล์เดิมไว้ที่: $backup$note" 2>/dev/null || true)"
  [[ "$choice" == "$copy_label" ]] && copy_text "$new_id"
  return 0
}

copy_text() {
  if [[ -n "${WAYLAND_DISPLAY:-}" ]] && command -v wl-copy >/dev/null; then
    printf '%s' "$1" | wl-copy
  elif command -v xclip >/dev/null; then
    printf '%s' "$1" | xclip -selection clipboard
  elif command -v xsel >/dev/null; then
    printf '%s' "$1" | xsel --clipboard --input
  else
    return 0
  fi
  notify-send -i anydesk "$APP_NAME" "คัดลอก ID $1 แล้ว" 2>/dev/null || true
}

# ---------- โหมด terminal ----------

run_cli() {
  if (( EUID != 0 )); then
    exec sudo "$SELF" --cli
  fi
  local ans pw1 pw2
  echo "AnyDesk ID ปัจจุบัน: $(get_id || true)"
  echo "คำเตือน: คนที่ remote เข้าเครื่องนี้ผ่าน AnyDesk จะหลุด และรหัส Unattended Access เดิมจะหาย"
  read -rp "พิมพ์ yes เพื่อรีเซ็ต ID: " ans
  [[ "$ans" == "yes" ]] || { echo "ยกเลิก"; exit 0; }
  while true; do
    read -rsp "รหัส Unattended Access ใหม่ (Enter = ไม่ตั้ง): " pw1; echo
    [[ -z "$pw1" ]] && break
    read -rsp "ยืนยันรหัส: " pw2; echo
    if [[ "$pw1" != "$pw2" ]]; then echo "รหัสไม่ตรงกัน"; continue; fi
    if (( ${#pw1} < 8 )); then echo "ต้องมีอย่างน้อย 8 ตัวอักษร"; continue; fi
    break
  done
  printf '%s\n' "$pw1" | do_reset cli | sed -e 's/^NEWID=/AnyDesk ID ใหม่ : /' -e 's/^OLDID=/AnyDesk ID เดิม : /' \
    -e 's/^BACKUP=/สำรองไฟล์เดิม  : /' -e 's/^ERROR=/ผิดพลาด: /' -e 's/^PWFAIL=1/ตั้งรหัส Unattended ไม่สำเร็จ/'
  return "${PIPESTATUS[1]}"
}

case "${1:-}" in
  --reset)
    # ปิดหน้าต่าง progress เสมอ แม้ reset ล้มกลางทาง
    [[ "${2:-}" == "gui" ]] && trap 'echo 100' EXIT
    do_reset "${2:-cli}" ;;
  --install)   do_install ;;
  --uninstall) do_uninstall ;;
  --cli)       run_cli ;;
  -h|--help)   sed -n '2,5p' "$SELF" | sed 's/^# \{0,1\}//' ;;
  "")
    if [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]] && (( EUID != 0 )) && command -v zenity >/dev/null; then
      run_gui
    else
      run_cli
    fi ;;
  *) echo "ไม่รู้จักตัวเลือก: $1 (ดู --help)"; exit 2 ;;
esac
