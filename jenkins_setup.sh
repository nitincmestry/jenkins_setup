#!/bin/bash
set -e

echo "[+] Updating system and installing prerequisites..."
apt update && apt install -y ca-certificates curl gnupg lsb-release git

echo "[+] Adding Docker's official GPG key..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo "[+] Adding Docker repository..."
echo \
  "deb [arch=$(dpkg --print-architecture) \
  signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list

echo "[+] Installing Docker Engine and Docker Compose plugin..."
apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "[+] Creating /opt/jenkins directory..."
mkdir -p /opt/jenkins/{jenkins,nginx}
cd /opt/jenkins

echo "[+] Writing docker-compose.yml..."
cat > docker-compose.yml <<'EOF'
version: '3.8'

services:
  jenkins:
    image: jenkins/jenkins:lts
    container_name: jenkins-master
    restart: unless-stopped
    user: root
    ports:
      - "50000:50000"
    volumes:
      - jenkins_home:/var/jenkins_home
      - /var/run/docker.sock:/var/run/docker.sock

  nginx:
    build:
      context: ./nginx
    container_name: nginx-proxy
    restart: unless-stopped
    ports:
      - "80:80"
    depends_on:
      - jenkins

volumes:
  jenkins_home:
EOF

echo "[+] Writing NGINX reverse proxy config..."
cat > nginx/default.conf <<EOF
server {
    listen 80;
    server_name pipemaster.ncm.com;

    location / {
        proxy_pass         http://jenkins:8080;
        proxy_set_header   Host \$host;
        proxy_set_header   X-Real-IP \$remote_addr;
        proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
    }
}
EOF

echo "[+] Writing NGINX Dockerfile..."
cat > nginx/Dockerfile <<EOF
FROM nginx:alpine
COPY default.conf /etc/nginx/conf.d/default.conf
EOF

echo "[+] Starting Jenkins and NGINX using Docker Compose..."
docker compose up -d

echo "[+] Waiting 30 seconds for Jenkins to initialize..."
sleep 30

echo "[+] Initial Jenkins admin password:"
docker exec jenkins-master cat /var/jenkins_home/secrets/initialAdminPassword || echo "Could not retrieve password."

echo ""
echo "[✔] Setup complete."
echo "→ Access Jenkins at: http://pipemaster1.fyre.ibm.com"
echo "→ If DNS is not configured, add this to your local /etc/hosts:"
echo ""
echo "    YOUR_SERVER_IP pipemaster1.fyre.ibm.com"
echo ""
