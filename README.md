# Ubuntu Minikube Installation

This repository contains a script to automate the installation and configuration of Minikube on an Ubuntu server. It sets up Docker, cri-dockerd, CNI plugins, crictl, Minikube, and kubectl, and configures the Kubernetes Dashboard with external access via Ingress.

## Prerequisites

*   **OS:** Ubuntu Server (tested on recent versions).
*   **Privileges:** Root or sudo access is required.
*   **Hardware:** Sufficient resources to run Minikube (at least 2 CPUs and 2GB RAM recommended).
*   **Domain:** The script configures Ingress for `<YOUR_DOMAIN>`. You must update this in the script or configure your `/etc/hosts` or DNS to point `<YOUR_DOMAIN>` to your server's IP.

## Installation

1.  **Clone the repository:**

    ```bash
    git clone https://github.com/yourusername/ubuntu-minikube-installation.git
    cd ubuntu-minikube-installation
    ```

2.  **Make the script executable:**

    ```bash
    chmod +x install_minikube.sh
    ```

3.  **Run the installation script:**

    ```bash
    ./install_minikube.sh
    ```

## What the Script Does

The `install_minikube.sh` script performs the following steps:

1.  **System Update:** Updates and upgrades Ubuntu packages.
2.  **Dependencies:** Installs basic tools like `curl`, `wget`, `git`, `socat`, and `apache2-utils` (for `htpasswd`).
3.  **Docker:** Installs Docker and configures it to run on startup.
4.  **cri-dockerd:** Installs `cri-dockerd` to allow Minikube to use Docker as the container runtime (since Kubernetes deprecated the dockershim).
5.  **CNI Plugins:** Installs standard Container Network Interface plugins.
6.  **crictl:** Installs the CLI for CRI-compatible container runtimes.
7.  **Minikube & kubectl:** Downloads and installs the latest versions of Minikube and kubectl.
8.  **Start Minikube:** Starts a Minikube cluster using the `none` driver (running directly on the host).
9.  **Kubeconfig:** Sets up `~/.kube/config` for both the current user and root.
10. **Addons:** Enables essential Minikube addons: `dashboard`, `default-storageclass`, `metrics-server`, `storage-provisioner`, and `ingress`.
11. **Dashboard Access:**
    *   Creates a `ServiceAccount` and `ClusterRoleBinding` for admin access.
    *   **Prompts for a username and password** to create a Basic Auth secret (`dash-auth`).
    *   Deploys an Ingress resource to expose the dashboard at `<YOUR_DOMAIN>`.

## Accessing the Dashboard

1.  **DNS/Hosts:** Ensure `<YOUR_DOMAIN>` resolves to your server's IP address.
2.  **Browser:** Navigate to `https://<YOUR_DOMAIN>`.
3.  **Basic Auth:** Enter the username and password you defined during the script execution.
4.  **Certificate Warning:** You will see a security warning because the Ingress uses a self-signed certificate. Accept the risk to proceed.
5.  **Login:** Once authenticated via Basic Auth, you should be able to access the dashboard.

## Troubleshooting

*   **Minikube fails to start:** Check if Docker is running (`sudo systemctl status docker`). Ensure you are not running as root if using a driver other than `none` (though this script uses `none` which requires root privileges for some operations, handled via `sudo`).
*   **Ingress not working:** Check if the Ingress controller is running: `kubectl get pods -n ingress-nginx`.
*   **Permission denied:** Ensure you ran the script with sufficient permissions or that your user is in the `docker` group (the script attempts to add the user). You might need to log out and log back in for group changes to take effect.

## License

[MIT](LICENSE)
