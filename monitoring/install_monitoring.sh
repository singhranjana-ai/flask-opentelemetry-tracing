
#!/bin/bash

set -e

# --------------------------------
# Check root user
# --------------------------------

if [ "$EUID" -ne 0 ]; then
    echo "Please run this script as root"
    exit 1
fi

echo "Installing monitoring components..."

# --------------------------------
# Check architecture
# --------------------------------

if [ "$(uname -m)" != "x86_64" ]; then
    echo "This script requires x86_64 architecture"
    exit 1
fi

# --------------------------------
# Check configuration files
# --------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

for FILE in otel-collector.yaml tempo.yaml grafana-datasource.yaml
do
    if [ ! -f "$SCRIPT_DIR/$FILE" ]; then
        echo "ERROR: $FILE not found in monitoring directory"
        exit 1
    fi
done

echo "Configuration files found."

# --------------------------------
# Install required packages
# --------------------------------

dnf install -y wget curl tar

# --------------------------------
# Install OpenTelemetry Collector
# --------------------------------

echo "Installing OpenTelemetry Collector..."

OTEL_VERSION="0.162.0"

curl -fL -o /tmp/otelcol.rpm \
"https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v${OTEL_VERSION}/otelcol_${OTEL_VERSION}_linux_amd64.rpm"

dnf install -y /tmp/otelcol.rpm

# --------------------------------
# Install Grafana Tempo
# --------------------------------

echo "Installing Grafana Tempo..."

TEMPO_VERSION="3.1.1"

curl -fL -o /tmp/tempo.tar.gz \
"https://github.com/grafana/tempo/releases/download/v${TEMPO_VERSION}/tempo_${TEMPO_VERSION}_linux_amd64.tar.gz"

mkdir -p /tmp/tempo-install

tar -xzf /tmp/tempo.tar.gz -C /tmp/tempo-install

install -m 755 /tmp/tempo-install/tempo /usr/local/bin/tempo

# --------------------------------
# Create Tempo user
# --------------------------------

id tempo &>/dev/null || useradd --system --no-create-home tempo

# --------------------------------
# Create Tempo storage directories
# --------------------------------

mkdir -p /var/lib/tempo/wal
mkdir -p /var/lib/tempo/blocks
mkdir -p /etc/tempo

chown -R tempo:tempo /var/lib/tempo

# --------------------------------
# Install Grafana
# --------------------------------

echo "Installing Grafana..."

curl -fL -o /tmp/grafana.gpg \
https://rpm.grafana.com/gpg.key

rpm --import /tmp/grafana.gpg

cat > /etc/yum.repos.d/grafana.repo <<EOF
[grafana]
name=Grafana
baseurl=https://rpm.grafana.com
repo_gpgcheck=1
enabled=1
gpgcheck=1
gpgkey=https://rpm.grafana.com/gpg.key
sslverify=1
EOF

dnf install -y grafana

# --------------------------------
# Copy configuration files
# --------------------------------

echo "Copying configuration files..."

mkdir -p /etc/otelcol
mkdir -p /etc/grafana/provisioning/datasources

cp "$SCRIPT_DIR/otel-collector.yaml" \
/etc/otelcol/config.yaml

cp "$SCRIPT_DIR/tempo.yaml" \
/etc/tempo/tempo.yaml

cp "$SCRIPT_DIR/grafana-datasource.yaml" \
/etc/grafana/provisioning/datasources/tempo.yaml

# --------------------------------
# Create Tempo systemd service
# --------------------------------

cat > /etc/systemd/system/tempo.service <<EOF
[Unit]
Description=Grafana Tempo
After=network.target

[Service]
User=tempo
Group=tempo
ExecStart=/usr/local/bin/tempo -config.file=/etc/tempo/tempo.yaml -target=all
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# --------------------------------
# Start services
# --------------------------------

echo "Starting monitoring services..."

systemctl daemon-reload

systemctl enable tempo
systemctl enable otelcol
systemctl enable grafana-server

systemctl restart tempo
systemctl restart otelcol
systemctl restart grafana-server

# --------------------------------
# Installation completed
# --------------------------------

echo "--------------------------------"
echo "Monitoring installation completed"
echo "--------------------------------"

echo "Tempo: http://localhost:3200"
echo "Grafana: http://localhost:3000"
echo "Collector: Port 4318"

echo ""
echo "Check services:"

echo "systemctl status tempo"
echo "systemctl status otelcol"
echo "systemctl status grafana-server"

echo ""
echo "Installation successful!"
