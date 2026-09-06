# devops-build — Production Deployment

A React application (served as a static, pre-built site) containerized with Docker/Nginx, deployed to AWS EC2, with a Jenkins CI/CD pipeline that builds and pushes images to Docker Hub, and Prometheus/Grafana monitoring with alerting on downtime.

## Live Demo

- **Deployed site:** http://\<EC2_PUBLIC_IP\>
- **GitHub repo (dev branch):** https://github.com/\<username\>/devops-build/tree/dev
- **Docker Hub (dev, public):** https://hub.docker.com/r/\<dockerhub-username\>/devops-build-dev
- **Docker Hub (prod, private):** https://hub.docker.com/r/\<dockerhub-username\>/devops-build-prod

## Architecture

```
Developer → git push (dev/master) → GitHub → Webhook
                                                 │
                                                 ▼
                                        Jenkins Pipeline
                                    (checkout → build → push)
                                                 │
                              ┌──────────────────┴──────────────────┐
                              ▼                                     ▼
                     Docker Hub: *-dev (public)          Docker Hub: *-prod (private)
                        (on push to dev)                    (on merge to master)
                              │                                     │
                              └──────────────────┬──────────────────┘
                                                  ▼
                                     Jenkins → SSH → AWS EC2 (t3.micro)
                                     docker pull + docker run -p 80:80
                                                  │
                                                  ▼
                                Prometheus (scrapes app + node_exporter)
                                                  │
                                        ┌─────────┴─────────┐
                                        ▼                   ▼
                                    Grafana            Alertmanager
                                 (dashboards)        → notifies on DOWN
```

## Repository Structure

```
devops-build/
├── build/                 # Pre-built static React app (HTML/CSS/JS)
├── Dockerfile              # Nginx image serving build/
├── nginx.conf              # SPA routing + caching config
├── docker-compose.yml       # Local/manual run definition
├── monitoring/
│   ├── docker-compose.yml     # Prometheus + Grafana + Alertmanager + node_exporter
│   ├── prometheus.yml          # Scrape config
│   ├── alertmanager.yml         # Alert routing (e.g. email/Slack on DOWN)
│   └── grafana/
│       └── provisioning/          # Datasources & dashboards as code
├── .dockerignore
├── .gitignore
├── build.sh                 # Build & push image to correct Docker Hub repo
├── deploy.sh                 # Pull & (re)start container on the server
├── Jenkinsfile                # CI/CD pipeline definition
└── README.md
```

## How the Branching → Docker Hub Mapping Works

| Git branch | Trigger            | Docker Hub repo         | Visibility |
|------------|---------------------|--------------------------|------------|
| `dev`      | push to `dev`        | `devops-build-dev`        | Public     |
| `master`   | merge `dev`→`master`   | `devops-build-prod`         | Private    |

## Local Development / Manual Run

```bash
git clone https://github.com/<username>/devops-build.git
cd devops-build
docker build -t devops-build:local .
docker run -d -p 80:80 devops-build:local
# or
docker compose up -d
```
Visit http://localhost.

## Build & Push (manual)

```bash
chmod +x build.sh deploy.sh
export DOCKERHUB_PASS="dockerhub-password-or-token"
./build.sh      # builds and pushes to the dev or prod repo based on current branch
```

## Deploy on the Server (manual)

```bash
./deploy.sh     # pulls latest image and (re)starts the container on port 80
```

## CI/CD (Jenkins)

The `Jenkinsfile` in this repo defines a 4-stage pipeline:

1. **Checkout** — pulls the branch that triggered the build
2. **Determine target repo** — `dev` branch → `*-dev` image, `master` → `*-prod` image
3. **Build & push** — builds the Docker image and pushes `:<build-number>` and `:latest` tags to Docker Hub
4. **Deploy** — SSHes into the EC2 instance, pulls the new image, and restarts the container

Jenkins is triggered automatically via a GitHub webhook on every push to `dev` or `master`.

Required Jenkins credentials:
| ID              | Type                        | Used for                     |
|------------------|------------------------------|-------------------------------|
| `dockerhub-creds` | Username & password           | `docker login` / push          |
| `ec2-ssh-key`      | SSH username with private key   | Deploying to EC2 over SSH        |

## Infrastructure

- **Compute:** AWS EC2 `t2.micro` (Ubuntu 22.04, Free Tier)
- **Security Group:**
  - `80/tcp` (HTTP) — open to `0.0.0.0/0` — public app access
  - `22/tcp` (SSH) — restricted to the administrator's IP only
  - `8080/tcp` (Jenkins UI) — restricted to the administrator's IP only
  - `9090/tcp` (Prometheus UI) — restricted to the administrator's IP only
  - `3000/tcp` (Grafana UI) — restricted to the administrator's IP only
  - `9093/tcp` (Alertmanager UI) — restricted to the administrator's IP only

## Monitoring

[Prometheus](https://prometheus.io/) + [Grafana](https://grafana.com/) (both open source, self-hosted) replace Uptime Kuma for metrics and alerting:

- **node_exporter** runs on the EC2 host and exposes system metrics (CPU, memory, disk, network) on `:9100`.
- **Prometheus** scrapes `node_exporter` (and, optionally, an HTTP blackbox probe of the deployed site on `:80`) every 15–30s and evaluates alerting rules.
- **Alertmanager** receives firing alerts from Prometheus and sends a notification only when the target transitions to **DOWN** (and again on recovery), so there's no noise while the app is healthy — the same behavior as before, just backed by Prometheus alert rules instead of Uptime Kuma's built-in checks.
- **Grafana** is provisioned with Prometheus as a datasource and a dashboard visualizing uptime, response time, and host resource usage.

`monitoring/docker-compose.yml`:
```bash
cd monitoring
docker compose up -d   # brings up prometheus, grafana, alertmanager, node_exporter
```

`monitoring/prometheus.yml` (example scrape config):
```yaml
global:
  scrape_interval: 15s

alerting:
  alertmanagers:
    - static_configs:
        - targets: ["alertmanager:9093"]

rule_files:
  - "alerts.yml"

scrape_configs:
  - job_name: "node"
    static_configs:
      - targets: ["node_exporter:9100"]

  - job_name: "blackbox_http"
    metrics_path: /probe
    params:
      module: [http_2xx]
    static_configs:
      - targets: ["http://<EC2_PUBLIC_IP>"]
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: blackbox_exporter:9115
```

Example alert rule (`monitoring/alerts.yml`) firing when the site is down for 1 minute:
```yaml
groups:
  - name: uptime
    rules:
      - alert: SiteDown
        expr: probe_success{job="blackbox_http"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Deployed site is DOWN"
```

Dashboards:
- Prometheus: http://\<EC2_PUBLIC_IP\>:9090
- Grafana: http://\<EC2_PUBLIC_IP\>:3000
- Alertmanager: http://\<EC2_PUBLIC_IP\>:9093

## Screenshots

## Screenshot Checklist

### 1. Application Setup

Terminal showing `git clone` and repo folder




<img width="634" height="387" alt="image" src="https://github.com/user-attachments/assets/ad2de697-d207-4733-8615-848af5778ee0" />

Browser showing React app running on http://localhost:34109
<img width="1917" height="657" alt="image" src="https://github.com/user-attachments/assets/47a9748e-8157-41ff-9733-7550a12437c2" />


### 2. Dockerization
Terminal output of `docker build`
<img width="926" height="75" alt="image" src="https://github.com/user-attachments/assets/de2dd9dd-0e81-4d16-9a50-6f6a5232232a" />

Terminal output of `docker images`
<img width="931" height="186" alt="image" src="https://github.com/user-attachments/assets/d4c4d529-081d-443c-bfce-6b190eab5d41" />

### 3. Bash Scripts
Terminal execution of `./build.sh`
<img width="951" height="216" alt="image" src="https://github.com/user-attachments/assets/523e019a-bef9-41f2-bf5d-52b41c2e816f" />


Terminal execution of `./deploy.sh`
<img width="936" height="452" alt="image" src="https://github.com/user-attachments/assets/149c04be-9dd8-4d6c-9258-7d2410f98475" />


### 4. Version Control
Terminal output of `git push origin dev`
<img width="887" height="241" alt="image" src="https://github.com/user-attachments/assets/db45f30a-805e-4abd-a236-94fc3dead6f1" />

GitHub repo page showing `dev` branch
<img width="1337" height="533" alt="image" src="https://github.com/user-attachments/assets/e235b58d-5ddf-402c-9140-b4fdb5ff400f" />


### 5. Docker Hub
Docker Hub repo list (showing `dev` public, `prod` private)
<img width="1913" height="377" alt="image" src="https://github.com/user-attachments/assets/996895e2-82c1-4170-b3a7-d81e2b0475ed" />

Repo page showing pushed image tags (`latest`, versioned tags)
	

      
	
<img width="673" height="723" alt="image" src="https://github.com/user-attachments/assets/0709711b-8736-4796-bc63-cea6ed56cda3" />


### 6. Jenkins CI/CD
Jenkins login page
<img width="1902" height="450" alt="image" src="https://github.com/user-attachments/assets/1fef5ba2-c4b6-429e-8e39-10633384432e" />

Jenkins pipeline configuration (triggers for dev/master)

	
	


<img width="824" height="530" alt="image" src="https://github.com/user-attachments/assets/ed438486-f976-470d-b306-8f0a164e68e6" />

Build execution logs (showing image build & push steps)




<img width="922" height="803" alt="image" src="https://github.com/user-attachments/assets/7e693ac2-3ee0-48b9-9c8e-f53f3e40d1b6" />


### 7. AWS Deployment
AWS EC2 Console (instance details)
<img width="1917" height="750" alt="image" src="https://github.com/user-attachments/assets/4f9e8e93-b81f-4676-90a1-5422d2f72c12" />


### 8.  Monitoring Screenshot 

|---|------------|
| 1 | Grafana login page |

<img width="1917" height="512" alt="image" src="https://github.com/user-attachments/assets/ab26c8cd-8fce-44c7-9ad0-482eaa9052c9" />

| 2 | Infinity data source — Save & test success |

<img width="1917" height="943" alt="image" src="https://github.com/user-attachments/assets/c3311427-6040-48c6-ad9c-343a779e0f9b" />

| 3 | Alert rule configuration |

<img width="1501" height="607" alt="image" src="https://github.com/user-attachments/assets/686671bd-3fd1-4f22-912a-9cce95013aca" />

| 4 | Alert rule in "Firing" state |

<img width="1917" height="747" alt="image" src="https://github.com/user-attachments/assets/9b466691-adad-4f20-bbdc-71e5afa77814" />

| 5 | Down-alert email |

<img width="1582" height="717" alt="image" src="https://github.com/user-attachments/assets/4e54eb34-d47f-4e55-97f9-fe51212abd99" />

| 6 | Resolved email |

<img width="1556" height="342" alt="image" src="https://github.com/user-attachments/assets/4425bac0-4ae9-4e75-beff-ce2d1a1029e1" />

