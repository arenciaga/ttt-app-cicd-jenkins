# Jenkins CI/CD Pipeline for Tic Tac Toe

A three-stage Jenkins pipeline for a Node.js Tic Tac Toe app. The pipeline tests changes on `dev`, merges passing changes into `main`, then deploys the tested app to an Ubuntu EC2 instance.

**Live app:** [http://34.245.201.21:3000](http://34.245.201.21:3000)

---

## What this project does

This project shows a practical CI/CD workflow rather than a single “build and deploy” script.

The flow is:

1. A developer pushes a change to the `dev` branch.
2. Jenkins runs the test job against `dev`.
3. If the tests pass, Jenkins merges `dev` into `main`.
4. Jenkins tests the merged `main` branch.
5. If the merge build is stable, Jenkins copies the app to EC2.
6. The EC2 instance installs dependencies and restarts the app with PM2.

The important part is that `main` only receives code that has passed the pipeline.

---

## Tech stack

| Tool | Role |
|---|---|
| GitHub | Source control, branch workflow, webhook trigger |
| Jenkins | CI/CD orchestration |
| AWS EC2 | Application host |
| Terraform | Infrastructure provisioning |
| Node.js 20 | Runtime for the Tic Tac Toe app |
| PM2 | Keeps the Node.js process running |
| rsync | Copies tested app files from Jenkins to EC2 |
| SSH | Allows Jenkins to run deployment commands on EC2 |

---

## Pipeline architecture

```mermaid
flowchart TD
    A[Push change to dev] --> B[GitHub webhook]
    B --> C[Job 1: CI test]
    C --> D[Checkout dev]
    D --> E[npm install and npm test]
    E -->|Tests pass| F[Job 2: Merge and test]
    E -->|Tests fail| X[Stop pipeline]

    F --> G[Checkout main]
    G --> H[Merge dev into main]
    H --> I[Run tests again]
    I --> J[Push main to GitHub]

    J --> K[Job 3: Deploy]
    K --> L[Checkout main]
    L --> M[rsync app files to EC2]
    M --> N[SSH into EC2]
    N --> O[Install dependencies]
    O --> P[Restart app with PM2]
    P --> Q[Updated app is live]
```

---

## Branch strategy

| Branch | Purpose |
|---|---|
| `dev` | Active development branch. New changes are pushed here first. |
| `main` | Deployable branch. Jenkins updates this branch only after tests pass. |

This keeps the production-style branch clean. A failed test stops at `dev` and does not reach `main`.

---

## Jenkins jobs

The pipeline is split into three Jenkins jobs. Keeping the jobs separate makes failures easier to locate: testing, merging, and deployment each have their own build history.

| Job | Jenkins job name | Main responsibility |
|---|---|---|
| Job 1 | `aryan-job1-ci-test` | Test changes pushed to `dev` |
| Job 2 | `aryan-job2-ci-merge-test` | Merge tested `dev` code into `main` and test again |
| Job 3 | `aryan-job3-cd-deploy` | Deploy the latest tested `main` build to EC2 |

---

## Job 1: CI test

Job 1 runs whenever GitHub sends a push event for the repository.

### Configuration

| Setting | Value |
|---|---|
| Repository | `https://github.com/arenciaga/ttt-app-cicd-jenkins` |
| Branch | `*/dev` |
| Trigger | GitHub hook trigger for GITScm polling |
| NodeJS version | Node.js 20 |

### Build script

```bash
node -v
npm -v

cd app
npm install
npm test
```

### Output

If the tests pass, Jenkins starts Job 2. If the tests fail, the pipeline stops before anything is merged into `main`.

---

## Job 2: Merge tested code into main

Job 2 runs only after Job 1 is stable. It pulls the latest `main`, merges in `dev`, runs the tests again, and pushes the updated `main` branch back to GitHub.

### Configuration

| Setting | Value |
|---|---|
| Repository | `https://github.com/arenciaga/ttt-app-cicd-jenkins` |
| Branch | `*/main` |
| Trigger | Build after `aryan-job1-ci-test` is stable |

### Jenkins credential

Job 2 needs permission to push to GitHub. The GitHub token is stored in Jenkins Credentials, not in the repository.

| Item | Value |
|---|---|
| Credential ID | `github-token-arenciaga` |
| Username variable | `GIT_USERNAME` |
| Password/token variable | `GIT_PASSWORD` |

### Build script

```bash
#!/bin/bash
set -e

echo "Starting Job 2: Merge dev into main and test"

git config user.name "Jenkins"
git config user.email "jenkins@example.com"

echo "Fetching latest branches"
git fetch origin

echo "Checking out main"
git checkout main
git pull origin main

echo "Merging dev into main"
git merge origin/dev --no-edit

echo "Installing dependencies and running tests"
cd app
npm install
npm test
cd ..

echo "Pushing merged main branch back to GitHub"
git push https://${GIT_USERNAME}:${GIT_PASSWORD}@github.com/arenciaga/ttt-app-cicd-jenkins.git main

echo "Job 2 completed successfully. Dev has been merged into main and pushed to GitHub."
```

### Output

If the merge and tests pass, Jenkins pushes the updated `main` branch and starts Job 3.

---

## Job 3: Deploy to EC2

Job 3 runs after Job 2 is stable. It deploys the tested `main` build to the EC2 app server.

The app is copied from the Jenkins workspace to EC2 with `rsync`. The production-style server does not clone the repository directly.

### Configuration

| Setting | Value |
|---|---|
| Repository | `https://github.com/arenciaga/ttt-app-cicd-jenkins` |
| Branch | `*/main` |
| Trigger | Build after `aryan-job2-ci-merge-test` is stable |

### Jenkins credential

Job 3 uses an SSH private key stored in Jenkins Credentials.

| Item | Value |
|---|---|
| Credential | `tech603-aryan-aws-key` |
| EC2 user | `ubuntu` |
| EC2 host | `34.245.201.21` |
| App directory | `/home/ubuntu/ttt-app` |

### Build script

```bash
#!/bin/bash
set -e

EC2_USER="ubuntu"
EC2_HOST="34.245.201.21"
APP_DIR="/home/ubuntu/ttt-app"

echo "Starting Job 3: Deploy tested main branch to EC2"

node -v
npm -v

echo "Copying app files from Jenkins workspace to EC2"
rsync -avz --delete \
  -e "ssh -o StrictHostKeyChecking=no" \
  app/ ${EC2_USER}@${EC2_HOST}:${APP_DIR}/

echo "Restarting app on EC2"
ssh -o StrictHostKeyChecking=no ${EC2_USER}@${EC2_HOST} << EOF
set -e

cd ${APP_DIR}

echo "Installing dependencies on EC2"
npm install

echo "Installing PM2 if missing"
sudo npm install -g pm2

echo "Stopping old app if running"
pm2 stop ttt-app || true
pm2 delete ttt-app || true

echo "Starting new app"
pm2 start index.js --name ttt-app

echo "Saving PM2 process list"
pm2 save

echo "Deployment complete on EC2"
EOF

echo "Job 3 completed successfully"
```

### Output

The tested version of the app is copied to EC2 and restarted with PM2.

**Deployment target:** [http://34.245.201.21:3000](http://34.245.201.21:3000)

---

## EC2 app server

| Setting | Value |
|---|---|
| Instance name | `tech603-aryan-jenkins-job3` |
| Operating system | Ubuntu 22.04 LTS |
| Runtime | Node.js 20 |
| Process manager | PM2 |
| Public IP | `34.245.201.21` |
| App port | `3000` |

### Security group access

| Port | Purpose |
|---|---|
| `22` | SSH access |
| `3000` | Node.js application |

---

## GitHub webhook

GitHub is configured to notify Jenkins when code is pushed.

```text
Webhook URL: http://34.254.6.118:8080/github-webhook/
Event: Push
```

Only Job 1 is triggered directly by the webhook. Job 2 and Job 3 are chained inside Jenkins and run only after the previous job succeeds.

---

## Run the app locally

Use the same runtime version as the Jenkins jobs and EC2 server.

```bash
cd app
npm install
npm test
node index.js
```

The deployed EC2 app runs on port `3000`.

---

## Deployment proof

Two homepage updates were pushed to the `dev` branch a few minutes apart to confirm that the full pipeline works end to end.

Each change followed this path:

```text
dev push
→ Job 1 tests dev
→ Job 2 merges dev into main
→ Job 3 deploys main to EC2
→ Homepage updates on the live server
```

Both updates were deployed to:

[http://34.245.201.21:3000](http://34.245.201.21:3000)

---

## Troubleshooting notes

| Problem | Where to check first |
|---|---|
| Job 1 fails | `npm install`, `npm test`, Node.js tool configuration |
| Job 2 fails | GitHub token, merge conflicts, branch checkout state |
| Job 3 fails | SSH credential, EC2 security group, `rsync`, PM2 logs |
| App is not reachable | EC2 public IP, port `3000`, PM2 process status |
| Webhook does not trigger | GitHub webhook delivery log and Jenkins webhook URL |

Useful PM2 commands on EC2:

```bash
pm2 list
pm2 logs ttt-app
pm2 restart ttt-app
```

---

## Security notes

- GitHub tokens and SSH keys should stay in Jenkins Credentials.
- Do not commit private keys, tokens, or `.env` files to the repository.
- In a production setup, restrict SSH access to trusted IP addresses only.
- `StrictHostKeyChecking=no` is convenient for a lab environment, but production deployments should use a known hosts file.

---

## What this project demonstrates

- Automated testing before merge
- Branch-gated deployment
- Jenkins job chaining
- GitHub webhook integration
- Secure credential use in Jenkins
- File-based deployment with `rsync`
- Process management with PM2
- A repeatable deployment path from GitHub to EC2

