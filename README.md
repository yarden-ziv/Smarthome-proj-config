# Smart Home Devices Management

This is the main repository for a system to view and manage Smart Home devices, such as lights, water heaters, or air conditioners. It is the project in the DevSecOps course at Bar-Ilan University
It is made up of three micro-services:

- Flask-based backend ([repository](https://github.com/yarden-ziv/Smarthome-proj-backend))
- React-based dashboard ([repository](https://github.com/yarden-ziv/Smarthome-proj-dashboard))
- Python-based device simulator ([repository](https://github.com/yarden-ziv/Smarthome-proj-simulator))

As well as monitoring and CI/CD (in this repository).

## Technologies Used

| Layer                 | Technology                          |
| --------------------- | ----------------------------------- |
| **API**               | Python3 • Flask • paho-mqtt • nginx |
| **Database**          | MongoDB hosted on Atlas             |
| **Device Simulation** | Python3 • paho-mqtt                 |
| **Frontend**          | React • Vite • nginx                |
| **Containerization**  | Docker • Docker Hub                 |
| **Orchestration**     | Kubernetes • minikube               |
| **Observability**     | Prometheus • Grafana                |
| **CI/CD**             | Jenkins                             |

## Usage

- To run the up on your machine from the pre-built images:

  - [Install minikube](https://minikube.sigs.k8s.io/docs/start/?arch=%2Fwindows%2Fx86-64%2Fstable%2F.exe+download)
  - Start minikube: `minikube start`
  - Clone this repo and apply the kubernetes manifests. On Windows, run PowerShell as administrator:
    ```powershell
    git clone https://github.com/yarden-ziv/Smarthome-proj-config
    cd Smarthome-proj-config\kubernetes
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
    .\setup.ps1 [-s]
    ```
    On Linux:
    ```bash
    git clone https://github.com/yarden-ziv/Smarthome-proj-config
    cd Smarthome-proj-config\kubernetes
    sudo swapoff -a
    chmod +x setup.sh
    ./setup.sh [-s]
    ```
  - Use `-s` to skip starting minikube, if it is already running.
  - Access the dashboard on your browser at `smart-home-dashboard.local`
  - To view the monitoring through grafana run `minikube service -n smart-home grafana-svc` 
    and log in using username: `admin`, password: `admin`.

- To run the different microservices locally, please refer to their individual README files.
