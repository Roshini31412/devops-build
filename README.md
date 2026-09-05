# devops-build — Production Deployment

A React application (served as a static, pre-built site) containerized with Docker/Nginx, deployed to AWS EC2, with a Jenkins CI/CD pipeline that builds and pushes images to Docker Hub, and Prometheus/Grafana monitoring with alerting on downtime.

## Live Demo

- **Deployed site:** http://\<EC2_PUBLIC_IP\>
- **GitHub repo (dev branch):** https://github.com/\<your-username\>/devops-build/tree/dev
- **Docker Hub (dev, public):** https://hub.docker.com/r/\<your-dockerhub-username\>/devops-build-dev
- **Docker Hub (prod, private):** https://hub.docker.com/r/\<your-dockerhub-username\>/devops-build-prod

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
                                     Jenkins → SSH → AWS EC2 (t2.micro)
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
├── screenshots/                 # Proof screenshots (see below)
└── README.md
```

## How the Branching → Docker Hub Mapping Works

| Git branch | Trigger            | Docker Hub repo         | Visibility |
|------------|---------------------|--------------------------|------------|
| `dev`      | push to `dev`        | `devops-build-dev`        | Public     |
| `master`   | merge `dev`→`master`   | `devops-build-prod`         | Private    |

## Local Development / Manual Run

```bash
git clone https://github.com/<your-username>/devops-build.git
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
export DOCKERHUB_PASS="your-dockerhub-password-or-token"
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

All proof screenshots live in [`/screenshots`](./screenshots):

- `jenkins-login.png`, `jenkins-config.png`, `jenkins-pipeline-console.png`
- `aws-ec2-console.png`, `aws-security-group.png`
- `dockerhub-dev-repo.png`, `dockerhub-prod-repo.png`
- `deployed-site.png`
- `prometheus-targets.png`, `grafana-dashboard.png`, `alertmanager-down-alert.png`

## Docker Images

| Environment | Image                                              |
|-------------|-----------------------------------------------------|
| Development | `<your-dockerhub-username>/devops-build-dev:latest`   |
| Production  | `<your-dockerhub-username>/devops-build-prod:latest`   |

## Tech Stack

Docker · Nginx · Jenkins · Docker Hub · AWS EC2 · Prometheus · Grafana · Alertmanager · Git/GitHub CLI
