# devops-build — Production Deployment

A React application (served as a static, pre-built site) containerized with Docker/Nginx, deployed to AWS EC2, with a Jenkins CI/CD pipeline that builds and pushes images to Docker Hub, and Uptime Kuma monitoring with down-alerts.

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
                                      Uptime Kuma monitors :80
                                      → notifies on DOWN only
```

## Repository Structure

```
devops-build/
├── build/                 # Pre-built static React app (HTML/CSS/JS)
├── Dockerfile              # Nginx image serving build/
├── nginx.conf              # SPA routing + caching config
├── docker-compose.yml       # Local/manual run definition
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
  - `3001/tcp` (Uptime Kuma UI) — restricted to the administrator's IP only

## Monitoring

[Uptime Kuma](https://github.com/louislam/uptime-kuma) (open source, self-hosted) polls the deployed site every 60 seconds over HTTP and sends a notification only on a status change to **DOWN** (and again when it recovers), so there is no noise while the app is healthy.

```bash
docker run -d --name uptime-kuma -p 3001:3001 -v uptime-kuma-data:/app/data \
  --restart unless-stopped louislam/uptime-kuma:1
```
Dashboard: http://\<EC2_PUBLIC_IP\>:3001

## Screenshots

All proof screenshots live in [`/screenshots`](./screenshots):

- `jenkins-login.png`, `jenkins-config.png`, `jenkins-pipeline-console.png`
- `aws-ec2-console.png`, `aws-security-group.png`
- `dockerhub-dev-repo.png`, `dockerhub-prod-repo.png`
- `deployed-site.png`
- `uptime-kuma-status.png`, `uptime-kuma-down-alert.png`

## Docker Images

| Environment | Image                                              |
|-------------|-----------------------------------------------------|
| Development | `<your-dockerhub-username>/devops-build-dev:latest`   |
| Production  | `<your-dockerhub-username>/devops-build-prod:latest`   |

## Tech Stack

Docker · Nginx · Jenkins · Docker Hub · AWS EC2 · Uptime Kuma · Git/GitHub CLI
