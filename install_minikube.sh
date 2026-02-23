#!/bin/bash

# Update and Upgrade Ubuntu
echo "Updating and upgrading system..."
sudo apt-get update -y
sudo apt-get upgrade -y

# Install basic dependencies
echo "Installing basic dependencies..."
sudo apt-get install -y curl wget apt-transport-https conntrack net-tools git socat apache2-utils

# Install Docker
echo "Installing Docker..."
sudo apt-get install -y docker.io
sudo systemctl enable --now docker
sudo usermod -aG docker $USER

# Install cri-dockerd
echo "Installing cri-dockerd..."
CRI_DOCKERD_VERSION="0.3.10"
if [ ! -f "/usr/local/bin/cri-dockerd" ]; then
  wget https://github.com/Mirantis/cri-dockerd/releases/download/v${CRI_DOCKERD_VERSION}/cri-dockerd-${CRI_DOCKERD_VERSION}.amd64.tgz
  tar xvf cri-dockerd-${CRI_DOCKERD_VERSION}.amd64.tgz
  sudo mv cri-dockerd/cri-dockerd /usr/local/bin/
  rm -rf cri-dockerd cri-dockerd-${CRI_DOCKERD_VERSION}.amd64.tgz

  # Configure systemd for cri-dockerd
  wget https://raw.githubusercontent.com/Mirantis/cri-dockerd/master/packaging/systemd/cri-docker.service
  wget https://raw.githubusercontent.com/Mirantis/cri-dockerd/master/packaging/systemd/cri-docker.socket
  sudo mv cri-docker.service /etc/systemd/system/
  sudo mv cri-docker.socket /etc/systemd/system/
  sudo sed -i -e 's,/usr/bin/cri-dockerd,/usr/local/bin/cri-dockerd,' /etc/systemd/system/cri-docker.service

  sudo systemctl daemon-reload
  sudo systemctl enable cri-docker.service
  sudo systemctl enable --now cri-docker.socket
else
  echo "cri-dockerd already installed."
fi

# Install CNI plugins
echo "Installing CNI plugins..."
CNI_PLUGINS_VERSION="v1.4.0"
if [ ! -d "/opt/cni/bin" ]; then
  sudo mkdir -p /opt/cni/bin
  wget https://github.com/containernetworking/plugins/releases/download/${CNI_PLUGINS_VERSION}/cni-plugins-linux-amd64-${CNI_PLUGINS_VERSION}.tgz
  sudo tar zxvf cni-plugins-linux-amd64-${CNI_PLUGINS_VERSION}.tgz -C /opt/cni/bin
  rm -f cni-plugins-linux-amd64-${CNI_PLUGINS_VERSION}.tgz
else
  echo "CNI plugins directory already exists."
fi

# Install crictl
echo "Installing crictl..."
VERSION="v1.32.0"
if [ ! -f "/usr/local/bin/crictl" ]; then
  wget https://github.com/kubernetes-sigs/cri-tools/releases/download/$VERSION/crictl-$VERSION-linux-amd64.tar.gz
  sudo tar zxvf crictl-$VERSION-linux-amd64.tar.gz -C /usr/local/bin
  rm -f crictl-$VERSION-linux-amd64.tar.gz
else
  echo "crictl already installed."
fi

# Install Minikube
echo "Installing Minikube..."
if [ ! -f "/usr/local/bin/minikube" ]; then
  curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
  sudo install minikube-linux-amd64 /usr/local/bin/minikube
  rm minikube-linux-amd64
else
  echo "Minikube already installed."
fi

# Install kubectl
echo "Installing kubectl..."
if [ ! -f "/usr/local/bin/kubectl" ]; then
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
  rm kubectl
else
  echo "kubectl already installed."
fi

# Check versions
echo "Minikube version:"
minikube version
echo "Kubectl version:"
kubectl version --client

# Start Minikube
echo "Starting Minikube..."
# The none driver requires root privileges.
# CHANGE_MINIKUBE_NONE_USER=true automatically updates permissions so you can use kubectl as a regular user.
export CHANGE_MINIKUBE_NONE_USER=true
sudo -E minikube start --driver=none

# Ensure kubeconfig is set up for both user and root
echo "Configuring kubeconfig..."
# Copy to root's kubeconfig so 'sudo kubectl' works
sudo mkdir -p /root/.kube
if [ -f "$HOME/.kube/config" ]; then
    sudo cp "$HOME/.kube/config" /root/.kube/config
    sudo chown root:root /root/.kube/config
    echo "Kubeconfig copied to /root/.kube/config"
else
    echo "Warning: $HOME/.kube/config not found. Minikube might not have started correctly."
fi

# Wait for API Server
echo "Waiting for API server to be ready..."
for i in {1..60}; do
   if sudo -E kubectl get po &> /dev/null; then
      echo "API Server is ready."
      break
   fi
   echo "Waiting for API server... ($i/60)"
   sleep 2
done

# Enable Addons
echo "Enabling Minikube addons..."
sudo -E minikube addons enable dashboard
sudo -E minikube addons enable default-storageclass
sudo -E minikube addons enable metrics-server
sudo -E minikube addons enable storage-provisioner
sudo -E minikube addons enable ingress

# Configure External Access to Dashboard
echo "Configuring external access to Dashboard..."

# 1. Create Admin Service Account
cat <<EOF | sudo -E kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kubernetes-dashboard
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kubernetes-dashboard
EOF

cat <<EOF | sudo -E kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: dashboard-ingress
  namespace: kubernetes-dashboard
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
spec:
  rules:
  - host: qrentradas.com  # This MUST match what you type in the browser
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: kubernetes-dashboard
            port:
              number: 80
EOF

# 3. Generate Token
echo "Generating login token..."
TOKEN=$(sudo -E kubectl -n kubernetes-dashboard create token admin-user --duration=8760h)

echo "Login Token:"
echo "$TOKEN"
echo "================================================================"
echo "Note: Since this uses a self-signed certificate, your browser"
echo "will warn you. You must accept the risk to proceed."
echo "================================================================"
