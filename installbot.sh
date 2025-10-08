#!/usr/bin/env bash
# installbot.sh
# Deploy agent.php + add* scripts to a VPS target from a GitHub Pages (CNAME) or other HTTPS host.

set -euo pipefail
IFS=$'\n\t'

######################
# CONFIG - EDIT HERE
######################
BASE_URL="${BASE_URL:-https://raw.githubusercontent.com/AdijayaTunneling/momok/main/}"   # GitHub Pages CNAME
FILES=( "agent.php" "addsshbot" "addwsbot" "addvlessbot" "addtrbot" "trialsshbot" "trialwsbot" "countall.py" )
WEB_ROOT="${WEB_ROOT:-/var/www/html}"
SCRIPTS_DIR="${SCRIPTS_DIR:-/usr/local/sbin}"
WEB_USER="${WEB_USER:-www-data}"
SUDOERS_FILE="/etc/sudoers.d/bot-scripts"
NGINX_SITE_PATH="/etc/nginx/sites-available/agent_bot"
LISTEN_ADDR="${LISTEN_ADDR:-0.0.0.0}"
LISTEN_PORT="${LISTEN_PORT:-8888}"  # default ke 8888
USE_CHECKSUM="${USE_CHECKSUM:-1}"
CLEAN_TMP=1

die(){ echo "ERROR: $*"; exit 1; }
info(){ echo "[*] $*"; }

# require root
if [[ "$(id -u)" -ne 0 ]]; then
  die "Script must be run as root (sudo)."
fi

TMPDIR="$(mktemp -d -t installbot.XXXXXXXX)" || die "Failed to create tmpdir"
info "Temp dir: ${TMPDIR}"

info "Using BASE_URL=${BASE_URL}"
info "Files to fetch: ${FILES[*]}"

# --- Install minimal prerequisites ---
info "Updating apt and installing prerequisites (nginx, php-fpm, python3, jq, wget, curl)..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y nginx php-fpm php-cli python3 python3-venv python3-pip jq wget curl ca-certificates ufw || true

# detect php-fpm service & socket
detect_php_svc_and_sock(){
  local svc sock
  for s in php8.2-fpm php8.1-fpm php8.0-fpm php7.4-fpm php7.2-fpm php-fpm; do
    if systemctl list-units --full -all | grep -q "^${s}.service"; then
      svc="$s"
      break
    fi
  done
  svc="${svc:-php7.4-fpm}"

  if [[ -S /run/php/php8.2-fpm.sock ]]; then sock="/run/php/php8.2-fpm.sock"; fi
  if [[ -S /run/php/php8.1-fpm.sock ]]; then sock="/run/php/php8.1-fpm.sock"; fi
  if [[ -S /run/php/php8.0-fpm.sock ]]; then sock="/run/php/php8.0-fpm.sock"; fi
  if [[ -S /run/php/php7.4-fpm.sock ]]; then sock="/run/php/php7.4-fpm.sock"; fi
  if [[ -z "${sock:-}" ]]; then sock="127.0.0.1:9000"; fi

  echo "${svc}:::${sock}"
}

read svc_and_sock <<< "$(detect_php_svc_and_sock)"
PHPFPM_SVC="${svc_and_sock%%::*}"
PHPFPM_SOCK="${svc_and_sock##*:::}"
info "Detected PHP-FPM service: ${PHPFPM_SVC}, socket: ${PHPFPM_SOCK}"

# --- Download files ---
info "Downloading files from ${BASE_URL} ..."
for f in "${FILES[@]}"; do
  url="${BASE_URL%/}/${f}"
  out="${TMPDIR}/${f}"
  info " - ${url}"
  if ! wget -q -O "${out}" "${url}"; then
    die "Failed to download ${url}"
  fi
  chmod u+r "${out}"
done

# --- Deploy agent.php ---
info "Deploying agent.php to ${WEB_ROOT}/agent.php"
mkdir -p "${WEB_ROOT}"
cp -f "${TMPDIR}/agent.php" "${WEB_ROOT}/agent.php"
chown root:"${WEB_USER}" "${WEB_ROOT}/agent.php"
chmod 0644 "${WEB_ROOT}/agent.php"

# --- Deploy scripts ---
info "Deploying scripts to ${SCRIPTS_DIR}"
mkdir -p "${SCRIPTS_DIR}"
for f in "${FILES[@]}"; do
  if [[ "${f}" == "agent.php" ]]; then continue; fi
  cp -f "${TMPDIR}/${f}" "${SCRIPTS_DIR}/${f}"
  chown root:root "${SCRIPTS_DIR}/${f}"
  chmod 0750 "${SCRIPTS_DIR}/${f}"
  info " - installed ${SCRIPTS_DIR}/${f}"
done

# --- Sudoers for web user ---
info "Writing sudoers file ${SUDOERS_FILE}"
cat > "${SUDOERS_FILE}" <<EOF
# Allow web user to run only the specific bot scripts without password
${WEB_USER} ALL=(ALL) NOPASSWD: \
${SCRIPTS_DIR}/addsshbot, \
${SCRIPTS_DIR}/addwsbot, \
${SCRIPTS_DIR}/addvlessbot, \
${SCRIPTS_DIR}/addtrbot, \
${SCRIPTS_DIR}/trialsshbot, \
${SCRIPTS_DIR}/trialwsbot, \
${SCRIPTS_DIR}/countall.py
EOF
chmod 0440 "${SUDOERS_FILE}"

# --- Nginx site ---
info "Creating nginx site at ${NGINX_SITE_PATH} listening ${LISTEN_ADDR}:${LISTEN_PORT}"
cat > "${NGINX_SITE_PATH}" <<NGINXCONF
server {
    listen ${LISTEN_ADDR}:${LISTEN_PORT} default_server;
    listen [::]:${LISTEN_PORT} default_server;
    server_name _;

    root ${WEB_ROOT};
    index index.php index.html index.htm;

    access_log /var/log/nginx/agent_access.log;
    error_log /var/log/nginx/agent_error.log;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:${PHPFPM_SOCK};
        fastcgi_read_timeout 300s;
    }
}
NGINXCONF

ln -sf "${NGINX_SITE_PATH}" /etc/nginx/sites-enabled/agent_bot

# restart services
info "Restarting ${PHPFPM_SVC} and nginx..."
systemctl restart "${PHPFPM_SVC}" || true
systemctl restart nginx || true

# --- Create agent.service (PHP built-in server alternative) ---
info "Creating systemd service: agent.service (PHP built-in server)"
cat > /etc/systemd/system/agent.service <<EOF
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
EOF

systemctl daemon-reload
systemctl enable agent
systemctl restart agent

# open firewall for LISTEN_PORT if ufw active
if command -v ufw >/dev/null 2>&1; then
  if ufw status | grep -q "Status: active"; then
    info "Allowing ${LISTEN_PORT}/tcp through ufw..."
    ufw allow "${LISTEN_PORT}/tcp" || true
  fi
fi

# quick test
info "Testing agent.php locally (curl http://127.0.0.1:${LISTEN_PORT}/agent.php?action=countall )"
curl -fsS "http://127.0.0.1:${LISTEN_PORT}/agent.php?action=countall" -o "${TMPDIR}/agent_count.json" || true
if [[ -s "${TMPDIR}/agent_count.json" ]]; then
  info "agent.php returned:"
  sed -n '1,200p' "${TMPDIR}/agent_count.json"
else
  info "agent.php did not return content. Check logs."
fi

# cleanup
[[ "${CLEAN_TMP}" -eq 1 ]] && rm -rf "${TMPDIR}"

info "Install finished."
info " - agent.php: http://${HOSTNAME:-127.0.0.1}:${LISTEN_PORT}/agent.php"
info " - Logs: /var/log/nginx/agent_error.log /var/log/nginx/agent_access.log"
info " - Service: systemctl status agent"
exit 0

