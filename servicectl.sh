#!/usr/bin/env bash
# servicectl.sh — install/uninstall a systemd service from the CLI
# Usage:
#   sudo ./servicectl.sh --install  --name NAME --exec "/abs/cmd args" [--user USER] [--desc DESC] [--env-file /etc/default/NAME] [--working-dir DIR] [--create-user]
#   sudo ./servicectl.sh --uninstall --name NAME [--purge-env] [--purge-user USER]
#
# Examples:
#   sudo ./servicectl.sh --install  --name hello-http \
#     --exec "/usr/bin/python3 -m http.server 8000 --bind 127.0.0.1 --directory /opt/hello-http" \
#     --user svcweb --desc "Hello HTTP test service" --create-user
#
#   sudo ./servicectl.sh --uninstall --name hello-http --purge-env --purge-user svcweb

set -Eeuo pipefail

[[ $EUID -ne 0 ]] && { echo "Please run as root (sudo)."; exit 1; }
command -v systemctl >/dev/null || { echo "systemd not detected; this script targets systemd hosts."; exit 2; }

ACTION=""
NAME=""
EXEC=""
RUN_AS="root"
DESC=""
ENV_FILE=""
WORKING_DIR=""
CREATE_USER=0
PURGE_ENV=0
PURGE_USER=""

MANIFEST_DIR="/var/lib/servicectl"
mkdir -p "$MANIFEST_DIR"

err() { echo "Error: $*" >&2; exit 1; }
info() { echo "-- $*"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install|install)   ACTION="install"; shift ;;
    --uninstall|uninstall) ACTION="uninstall"; shift ;;
    --name) NAME="${2:-}"; shift 2 ;;
    --exec) EXEC="${2:-}"; shift 2 ;;
    --user) RUN_AS="${2:-}"; shift 2 ;;
    --desc) DESC="${2:-}"; shift 2 ;;
    --env-file) ENV_FILE="${2:-}"; shift 2 ;;
    --working-dir) WORKING_DIR="${2:-}"; shift 2 ;;
    --create-user) CREATE_USER=1; shift ;;
    --purge-env) PURGE_ENV=1; shift ;;
    --purge-user) PURGE_USER="${2:-}"; shift 2 ;;
    -h|--help)
      sed -n '1,80p' "$0"; exit 0;;
    *) err "Unknown arg: $1";;
  esac
done

[[ -z "$ACTION" ]] && err "Choose --install or --uninstall"
[[ -z "$NAME" ]] && err "--name is required"

UNIT_PATH="/etc/systemd/system/${NAME}.service"
DEFAULT_ENV_FILE="/etc/default/${NAME}"
[[ -z "$ENV_FILE" ]] && ENV_FILE="$DEFAULT_ENV_FILE"
[[ -z "$DESC" ]] && DESC="${NAME} service"

install_service() {
  [[ -z "$EXEC" ]] && err "--exec \"<absolute command>\" is required for install"
  [[ "${EXEC:0:1}" != "/" ]] && echo "Warning: Exec command should be an absolute path." >&2

  if [[ $CREATE_USER -eq 1 ]]; then
    if id "$RUN_AS" &>/dev/null; then
      info "User $RUN_AS already exists (ok)."
    else
      info "Creating system user $RUN_AS"
      useradd --system --no-create-home --shell /usr/sbin/nologin "$RUN_AS"
    fi
  fi

  # Track whether we create the env file
  ENV_CREATED=0
  if [[ ! -f "$ENV_FILE" ]]; then
    install -o root -g root -m 0644 /dev/null "$ENV_FILE"
    echo "# Add KEY=value here for ${NAME}" > "$ENV_FILE"
    ENV_CREATED=1
  fi

  info "Writing unit to $UNIT_PATH"
  cat > "$UNIT_PATH" <<UNIT
[Unit]
Description=$DESC
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=$RUN_AS
Group=$RUN_AS
EnvironmentFile=-$ENV_FILE
ExecStart=$EXEC
Restart=on-failure
RestartSec=3
$( [[ -n "$WORKING_DIR" ]] && echo "WorkingDirectory=$WORKING_DIR" )

[Install]
WantedBy=multi-user.target
UNIT

  systemctl daemon-reload
  systemctl enable --now "${NAME}.service"

  # Write manifest so uninstall knows what we created
  MF="${MANIFEST_DIR}/${NAME}.manifest"
  {
    echo "UNIT_PATH=$UNIT_PATH"
    echo "ENV_FILE=$ENV_FILE"
    echo "ENV_CREATED=$ENV_CREATED"
    echo "RUN_AS=$RUN_AS"
    echo "DESC=$DESC"
    [[ -n "$WORKING_DIR" ]] && echo "WORKING_DIR=$WORKING_DIR"
  } > "$MF"

  info "Installed and started: ${NAME}.service"
  systemctl --no-pager --full status "${NAME}.service" || true
  echo "Tip: journalctl -u ${NAME} -f"
}

uninstall_service() {
  info "Stopping and disabling ${NAME}.service (if present)"
  systemctl stop "${NAME}.service" 2>/dev/null || true
  systemctl disable "${NAME}.service" 2>/dev/null || true

  MF="${MANIFEST_DIR}/${NAME}.manifest"
  ENV_CREATED=0
  if [[ -f "$MF" ]]; then
    # shellcheck disable=SC1090
    source "$MF"
  else
    info "No manifest found; proceeding with best-effort removal."
  fi

  if [[ -f "$UNIT_PATH" ]]; then
    info "Removing unit $UNIT_PATH"
    rm -f "$UNIT_PATH"
  else
    info "Unit not found at $UNIT_PATH (ok)."
  fi

  if [[ $PURGE_ENV -eq 1 ]]; then
    if [[ -f "$ENV_FILE" ]]; then
      info "Removing env file $ENV_FILE (--purge-env)"
      rm -f "$ENV_FILE"
    fi
  else
    if [[ "${ENV_CREATED:-0}" -eq 1 && -f "$ENV_FILE" ]]; then
      info "Removing env file $ENV_FILE (created by this script)"
      rm -f "$ENV_FILE"
    else
      info "Leaving env file ($ENV_FILE) in place."
    fi
  fi

  systemctl daemon-reload

  if [[ -n "$PURGE_USER" ]]; then
    if id "$PURGE_USER" &>/dev/null; then
      info "Removing user $PURGE_USER (--purge-user)"
      userdel "$PURGE_USER" || true
    else
      info "User $PURGE_USER does not exist (ok)."
    fi
  fi

  [[ -f "$MF" ]] && { info "Removing manifest $MF"; rm -f "$MF"; }

  info "Uninstall complete."
}

case "$ACTION" in
  install) install_service ;;
  uninstall) uninstall_service ;;
esac

