#!/bin/bash

set -euo pipefail

# Run as root so packages and system services can be installed.
if [ "${EUID}" -ne 0 ]; then
    echo "ERROR: Run this script as root: sudo bash install_monitoring.sh"
    exit 1
fi

if [ "$(uname -m)" != "x86_64" ]; then
    echo "ERROR: This lab installer currently supports x86_64 EC2 instances only."
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for FILE in otel-collector.yaml tempo.yaml grafana-datasource.yaml; do
    if [ ! -f "${SCRIPT_DIR}/${FILE}" ]; then
        echo "ERROR: ${FILE} is missing from ${SCRIPT_DIR}"
        exit 1
    fi
done

echo "Installing required packages..."
dnf install -y tar

# Amazon Linux 2023 commonly provides curl-minimal. Do not force-install
# the full curl package because it conflicts with curl-minimal.
if ! command -v curl >/dev/null 2>&1; then
    dnf install -y curl-minimal
fi

if ! command -v curl >/dev/null 2>&1; then
    echo "ERROR: curl command is still unavailable."
    exit 1
fi

# OpenTelemetry Collector
OTEL_VERSION="0.162.0"
echo "Installing OpenTelemetry Collector ${OTEL_VERSION}..."
curl -fL --retry 3 --retry-delay 2 -o /tmp/otelcol.rpm \
    "https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v${OTEL_VERSION}/otelcol_${OTEL_VERSION}_linux_amd64.rpm"
dnf install -y /tmp/otelcol.rpm

# Grafana Tempo
TEMPO_VERSION="3.1.1"
echo "Installing Grafana Tempo ${TEMPO_VERSION}..."
curl -fL --retry 3 --retry-delay 2 -o /tmp/tempo.tar.gz \
    "https://github.com/grafana/tempo/releases/download/v${TEMPO_VERSION}/tempo_${TEMPO_VERSION}_linux_amd64.tar.gz"
mkdir -p /tmp/tempo-install
tar -xzf /tmp/tempo.tar.gz -C /tmp/tempo-install
install -m 755 /tmp/tempo-install/tempo /usr/local/bin/tempo

# Dedicated unprivileged Tempo user and storage.
id tempo >/dev/null 2>&1 || useradd --system --no-create-home --shell /sbin/nologin tempo
mkdir -p /var/lib/tempo/wal /var/lib/tempo/blocks /etc/tempo
chown -R tempo:tempo /var/lib/tempo

# Grafana repository and package.
echo "Installing Grafana..."
curl -fL --retry 3 --retry-delay 2 -o /tmp/grafana.gpg https://rpm.grafana.com/gpg.key
rpm --import /tmp/grafana.gpg

cat > /etc/yum.repos.d/grafana.repo <<'REPO'
[grafana]
name=Grafana
baseurl=https://rpm.grafana.com
enabled=1
repo_gpgcheck=1
gpgcheck=1
gpgkey=https://rpm.grafana.com/gpg.key
sslverify=1
REPO

dnf install -y grafana

# Install the repository configuration files.
echo "Copying configuration files..."
mkdir -p /etc/otelcol /etc/grafana/provisioning/datasources
cp "${SCRIPT_DIR}/otel-collector.yaml" /etc/otelcol/config.yaml
cp "${SCRIPT_DIR}/tempo.yaml" /etc/tempo/tempo.yaml
cp "${SCRIPT_DIR}/grafana-datasource.yaml" /etc/grafana/provisioning/datasources/tempo.yaml

# Tempo systemd unit.
cat > /etc/systemd/system/tempo.service <<'UNIT'
[Unit]
Description=Grafana Tempo
Wants=network-online.target
After=network-online.target

[Service]
User=tempo
Group=tempo
ExecStart=/usr/local/bin/tempo -config.file=/etc/tempo/tempo.yaml -target=all
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

# Enable and start services.
echo "Enabling and starting monitoring services..."
systemctl daemon-reload
systemctl enable tempo otelcol grafana-server
systemctl restart tempo
systemctl restart otelcol
systemctl restart grafana-server

# Fail clearly if a service did not start.
for SERVICE in tempo otelcol grafana-server; do
    if ! systemctl is-active --quiet "${SERVICE}"; then
        echo "ERROR: ${SERVICE} did not start. Recent logs:"
        journalctl -u "${SERVICE}" -n 40 --no-pager || true
        exit 1
    fi
done

echo ""
echo "Monitoring installation completed successfully."
echo "Grafana:  http://<MONITORING_EC2_PUBLIC_IP>:3000"
echo "Tempo:    http://localhost:3200"
echo "OTLP/HTTP collector receiver: port 4318"
echo ""
echo "Service status:"
systemctl --no-pager --full status tempo otelcol grafana-server
