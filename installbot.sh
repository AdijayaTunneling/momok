#!/usr/bin/env bash
# installbot.sh — Deploy agent.php + bot scripts to a VPS
set -euo pipefail
IFS=$'\n\t'

######################
# CONFIG
######################
BASE_URL="${BASE_URL:-https://raw.githubusercontent.com/AdijayaTunneling/momok/main/}"
FILES=(
  agent.php
  addsshbot addwsbot addvlessbot addtrbot
  trialsshbot trialwsbot trialvlessbot trialtrbot
  countall.py cekloginbot cekloginall
)
WEB_ROOT="${WEB_ROOT:-/var/www/html}"
SCRIPTS_DIR="${SCRIPTS_DIR:-/usr/local/sbin}"
WEB_USER="${WEB_USER:-www-data}"
SUDOERS_FILE="/etc/sudoers.d/bot-scripts"
LISTEN_ADDR="${LISTEN_ADDR:-0.0.0.0}"
LISTEN_PORT="${LISTEN_PORT:-8888}"
CLEAN_TMP="${CLEAN_TMP:-1}"

die() { echo "ERROR: $*"; exit 1; }
info() { echo "[*] $*"; }

[[ "$(id -u)" -ne 0 ]] && die "Harus root"

TMPDIR="$(mktemp -d -t installbot.XXXXXXXX)" || die "gagal buat tmpdir"
trap '[[ "${CLEAN_TMP}" == 1 ]] && rm -rf "${TMPDIR}"' EXIT
info "Temp: ${TMPDIR}"

# ── Prerequisites ──────────────────────────────────────────
info "Install prerequisites..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y nginx php-fpm php-cli python3 jq wget curl ca-certificates ufw || true

# detect php-fpm
detect_php() {
  local svc sock
  for s in php8.2-fpm php8.1-fpm php8.0-fpm php7.4-fpm php7.2-fpm php-fpm; do
    systemctl list-units --full -all | grep -q "^${s}.service" && { svc="$s"; break; }
  done
  svc="${svc:-php7.4-fpm}"
  for s in /run/php/php8.2-fpm.sock /run/php/php8.1-fpm.sock /run/php/php8.0-fpm.sock /run/php/php7.4-fpm.sock; do
    [[ -S "$s" ]] && { sock="$s"; break; }
  done
  echo "${svc}:::${sock:-127.0.0.1:9000}"
}
IFS=':::' read -r PHPFPM_SVC PHPFPM_SOCK < <(detect_php)
info "PHP: ${PHPFPM_SVC} | socket: ${PHPFPM_SOCK}"

# ── Download ────────────────────────────────────────────────
info "Download ${#FILES[@]} files from ${BASE_URL}"
for f in "${FILES[@]}"; do
  info "  → ${f}"
  wget -q --timeout=30 -O "${TMPDIR}/${f}" "${BASE_URL%/}/${f}" || die "gagal download ${f}"
  [[ ! -s "${TMPDIR}/${f}" ]] && die "${f} kosong"
done

# ── Deploy agent.php ───────────────────────────────────────
info "Deploy agent.php → ${WEB_ROOT}/agent.php"
mkdir -p "${WEB_ROOT}"
cp -f "${TMPDIR}/agent.php" "${WEB_ROOT}/agent.php"
chown root:"${WEB_USER}" "${WEB_ROOT}/agent.php"
chmod 0644 "${WEB_ROOT}/agent.php"
php -l "${WEB_ROOT}/agent.php" || die "agent.php syntax error"

# ── Deploy scripts ─────────────────────────────────────────
info "Deploy scripts → ${SCRIPTS_DIR}"
mkdir -p "${SCRIPTS_DIR}"
for f in "${FILES[@]}"; do
  [[ "$f" == "agent.php" ]] && continue
  cp -f "${TMPDIR}/${f}" "${SCRIPTS_DIR}/${f}"
  chown root:root "${SCRIPTS_DIR}/${f}"
  chmod 0750 "${SCRIPTS_DIR}/${f}"
  # verify shebang & syntax
  case "$f" in
    *.py) python3 -c "import py_compile; py_compile.compile('${SCRIPTS_DIR}/${f}', doraise=True)" 2>/dev/null || die "${f} syntax error" ;;
    *)    bash -n "${SCRIPTS_DIR}/${f}" 2>/dev/null || die "${f} syntax error" ;;
  esac
  info "  ✓ ${f}"
done

# ── Sudoers (dynamic from FILES) ───────────────────────────
info "Sudoers → ${SUDOERS_FILE}"
{
  echo "# Allow ${WEB_USER} to run bot scripts without password"
  echo "${WEB_USER} ALL=(ALL) NOPASSWD: \\"
  # list all non-php files; last entry NO trailing backslash
  entries=()
  for f in "${FILES[@]}"; do
    [[ "$f" == "agent.php" ]] && continue
    entries+=( "${SCRIPTS_DIR}/${f}" )
  done
  for i in "${!entries[@]}"; do
    if [[ $i -lt $((${#entries[@]} - 1)) ]]; then
      echo "  ${entries[$i]}, \\"
    else
      echo "  ${entries[$i]}"
    fi
  done
} > "${SUDOERS_FILE}"
chmod 0440 "${SUDOERS_FILE}"
visudo -c -f "${SUDOERS_FILE}" || die "sudoers syntax error"

# ── Nginx ──────────────────────────────────────────────────
NGINX_CONF="/etc/nginx/sites-available/agent_bot"
info "Nginx → ${NGINX_CONF}"
cat > "${NGINX_CONF}" <<NGINXEOF
server {
    listen ${LISTEN_ADDR}:${LISTEN_PORT} default_server;
    listen [::]:${LISTEN_PORT} default_server;
    server_name _;
    root ${WEB_ROOT};
    index index.php index.html index.htm;
    access_log /var/log/nginx/agent_access.log;
    error_log /var/log/nginx/agent_error.log;
    location / { try_files \$uri \$uri/ =404; }
    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:${PHPFPM_SOCK};
        fastcgi_read_timeout 300s;
    }
}
NGINXEOF
ln -sf "${NGINX_CONF}" /etc/nginx/sites-enabled/agent_bot
systemctl restart "${PHPFPM_SVC}" || true
systemctl restart nginx || true

# ── agent.service (PHP built-in fallback) ──────────────────
info "Systemd agent.service"
cat > /etc/systemd/system/agent.service <<UNIT
[Unit]
Description=Agent PHP Service
After=network.target
[Service]
ExecStart=/usr/bin/php -S 0.0.0.0:${LISTEN_PORT} -t ${WEB_ROOT}/
WorkingDirectory=${WEB_ROOT}/
Restart=always
User=root
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable agent
systemctl restart agent

# ── UFW ────────────────────────────────────────────────────
command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active" && {
  ufw allow "${LISTEN_PORT}/tcp" || true
}

# ── Test ───────────────────────────────────────────────────
info "Test agent.php"
curl -fsS --max-time 5 "http://127.0.0.1:${LISTEN_PORT}/agent.php?action=countall" -o "${TMPDIR}/test.json" || true
if [[ -s "${TMPDIR}/test.json" ]]; then
  info "agent.php OK — $(head -c 200 "${TMPDIR}/test.json")"
else
  info "agent.php tidak ada response, cek log"
fi

# ── Summary ────────────────────────────────────────────────
info "==== Selesai ===="
info "  agent.php → http://<ip>:${LISTEN_PORT}/agent.php"
info "  scripts   → ${SCRIPTS_DIR}/  (${#entries[@]} file)"
info "  sudoers   → ${SUDOERS_FILE}"
info "  nginx log → /var/log/nginx/agent_*.log"
info "  service   → systemctl status agent"
exit 0
