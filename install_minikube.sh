#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

echo "------------------------------------------------------------"
echo "STARTING KUBERNETES BARE-METAL SETUP (Minikube driver=none)"
echo "------------------------------------------------------------"

# Update and Upgrade Ubuntu
echo "Updating and upgrading system..."
sudo apt-get update -y
sudo apt-get upgrade -y

# 1. KERNEL & SYSTEM PREPARATION
echo "Configuring kernel modules and sysctl..."
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# Disable swap (Kubernetes requirement)
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Networking sysctl: Disable RP filter and enable IP forwarding
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
net.ipv4.conf.all.rp_filter         = 0
net.ipv4.conf.default.rp_filter     = 0
EOF
sudo sysctl --system

# 2. FIREWALL & NETWORKING MODES
echo "Hardening networking rules..."
sudo ufw disable || true
sudo apt-get install -y iptables arptables ebtables
# Force legacy iptables to ensure compatibility with CNI
sudo update-alternatives --set iptables /usr/sbin/iptables-legacy
sudo update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
sudo iptables -P FORWARD ACCEPT

# 3. INSTALL DEPENDENCIES
echo "Installing base dependencies..."
sudo apt-get install -y curl wget apt-transport-https conntrack net-tools git socat apache2-utils ethtool

# 4. DOCKER & CRI-DOCKERD
echo "Installing Docker and cri-dockerd..."
sudo apt-get install -y docker.io
sudo systemctl enable --now docker
sudo usermod -aG docker $USER

CRI_DOCKERD_VERSION="0.3.10"
wget https://github.com/Mirantis/cri-dockerd/releases/download/v${CRI_DOCKERD_VERSION}/cri-dockerd-${CRI_DOCKERD_VERSION}.amd64.tgz
tar xvf cri-dockerd-${CRI_DOCKERD_VERSION}.amd64.tgz
sudo mv cri-dockerd/cri-dockerd /usr/local/bin/
rm -rf cri-dockerd cri-dockerd-${CRI_DOCKERD_VERSION}.amd64.tgz

wget https://raw.githubusercontent.com/Mirantis/cri-dockerd/master/packaging/systemd/cri-docker.service
wget https://raw.githubusercontent.com/Mirantis/cri-dockerd/master/packaging/systemd/cri-docker.socket
sudo mv cri-docker.service /etc/systemd/system/
sudo mv cri-docker.socket /etc/systemd/system/
sudo sed -i -e 's,/usr/bin/cri-dockerd,/usr/local/bin/cri-dockerd,' /etc/systemd/system/cri-docker.service
sudo systemctl daemon-reload
sudo systemctl enable --now cri-docker.socket

# 5. KUBERNETES TOOLS
echo "Installing Minikube and Kubectl..."
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube
rm minikube-linux-amd64

curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl

# 6. START MINIKUBE (NONE DRIVER)
echo "Starting Minikube..."
export CHANGE_MINIKUBE_NONE_USER=true
sudo -E minikube start --driver=none --container-runtime=docker --cri-socket=unix:///var/run/cri-docker.sock

# 7. POST-START VPS NETWORK HARDENING
echo "Disabling Checksum Offloading to prevent timeouts..."
sleep 15
# Target 'bridge' or 'cni0' - whichever was created
BRIDGE_INTF=$(ip addr | grep -E "bridge|cni0" | awk -F: '{print $2}' | tr -d ' ' | head -n 1)
if [ ! -z "$BRIDGE_INTF" ]; then
    sudo ethtool -K $BRIDGE_INTF tx off rx off || true
    echo "Offloading disabled on $BRIDGE_INTF"
fi

# 8. CONFIGURE KUBECONFIG
echo "Configuring permissions..."
sudo mkdir -p /root/.kube
sudo cp $HOME/.kube/config /root/.kube/config || true
sudo chown root:root /root/.kube/config || true

# 9. ENABLE ADDONS
echo "Enabling standard addons..."
sudo -E minikube addons enable dashboard
sudo -E minikube addons enable ingress
sudo -E minikube addons enable metrics-server
sudo -E minikube addons enable storage-provisioner

# 10. DNS STABILITY PATCH
echo "Patching CoreDNS for VPS reliability..."
# Wait for deployment to exist
timeout 120s bash -c 'until sudo kubectl -n kube-system get deployment coredns; do sleep 5; done'

# Force Google DNS as upstream to bypass problematic local VPS resolvers
sudo kubectl -n kube-system get configmap coredns -o yaml > coredns.yaml
sed -i 's/forward . \/etc\/resolv.conf/forward . 8.8.8.8 8.8.4.4/' coredns.yaml
sudo kubectl apply -f coredns.yaml
rm coredns.yaml
sudo kubectl -n kube-system rollout restart deployment coredns

echo "------------------------------------------------------------"
echo "INSTALLATION COMPLETE"
echo "Next Steps:"
echo "1. Run: sudo kubectl get pods -A"
echo "2. Deploy MariaDB and check connectivity with nc -zv"
echo "------------------------------------------------------------"