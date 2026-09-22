# Jenkins + Forgejo pipeline setup

This is a one-time setup checklist for wiring the `Jenkinsfile` in this repo
to your Jenkins and Forgejo instances. None of it is automated by this repo
itself - it touches shared Jenkins/Forgejo state, so it's deliberately a
manual, documented checklist rather than a script that reconfigures your
CI server.

## 1. Give the Jenkins agent access to Docker

The pipeline runs `docker build`/`docker push` directly (no Docker-in-Docker).
Whatever Jenkins agent runs this job needs the `docker` CLI and a reachable
Docker daemon. If you're running the stock `jenkins/jenkins:lts` image (as
in this environment), it ships **without** a Docker CLI or socket by
default. Two common ways to add it - pick one:

**A. Socket-mount + CLI in the existing Jenkins container** (simplest,
lets the Jenkins container control the *host's* Docker daemon - understand
that this is effectively root-equivalent on the host, since anything with
docker socket access can escape a container):
```yaml
# add to the jenkins service in its own docker-compose.yml
volumes:
  - /var/run/docker.sock:/var/run/docker.sock
  - jenkins_docker_bin:/usr/local/bin   # or install via a custom image layer
```
then install the `docker` CLI package inside the running container (or,
better, build a small custom image `FROM jenkins/jenkins:lts` that adds
`docker-cli` via `apt-get`).

**B. A dedicated Docker-capable agent**, connected to the Jenkins
controller over JNLP/SSH, labeled `docker`, with `agent { label 'docker' }`
in the `Jenkinsfile`. More isolation from the controller; more to stand up.
This repo's `Jenkinsfile` uses `agent any` for simplicity - change it to
`agent { label 'docker' }` if you go this route.

Either way, verify with a Pipeline step or `Execute shell` build:
```sh
docker version
```

## 2. Create a Forgejo access token for pushing images

In Forgejo: **Settings → Applications → Generate New Token**, scope
`write:package` (and `read:package`). Copy the token immediately - it's
shown once.

## 3. Add it as a Jenkins credential

**Manage Jenkins → Credentials → (System) → Global → Add Credentials**
- Kind: `Username with password`
- Username: your Forgejo username
- Password: the token from step 2
- ID: `forgejo-registry` (must match `REGISTRY_CREDENTIALS_ID` in the
  `Jenkinsfile`, or change one to match the other)

## 4. Create the pipeline job

**New Item → Multibranch Pipeline** (recommended, so PR/branch builds work
automatically), pointed at this repo's Forgejo URL, credentials = a
read-only token or SSH key for checkout. Branch Source detects
`Jenkinsfile` at the repo root automatically.

Set the job parameters (`REGISTRY`, `IMAGE_NAMESPACE`) to match your
Forgejo instance - defaults in the `Jenkinsfile` are
`[redacted]` / `CHANGE_ME`; set `IMAGE_NAMESPACE` to
whatever Forgejo owner/org you want the image published under.

## 5. Webhook: build on push

In Forgejo: repo → **Settings → Webhooks → Add Webhook → Forgejo**.
- Target URL: `http://<jenkins-host>:8080/multibranch-webhook-trigger/invoke?token=<your-token>`
  (if using the Multibranch Scan Webhook Trigger plugin) or the generic
  `http://<jenkins-host>:8080/forgejo-webhook/` if using the native Forgejo
  webhook plugin for Jenkins.
- Trigger: Push events (and Pull Request events, if you want PR builds).

Without a webhook, Jenkins still works via its periodic branch-indexing
poll - just slower to notice new commits.

## 6. Optional: scanning tools on the agent

The `Vulnerability scan` and `SBOM` stages check for `trivy`/`syft` on the
agent and log a clear warning + skip (they do not silently pretend to have
scanned) if missing. To make them real:

```sh
# Trivy
wget -qO- https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin

# Syft
curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b /usr/local/bin

# hadolint (Dockerfile lint, "Verify" stage)
wget -O /usr/local/bin/hadolint https://github.com/hadolint/hadolint/releases/latest/download/hadolint-Linux-x86_64
chmod +x /usr/local/bin/hadolint
```

Install these on whatever host/agent actually runs the pipeline steps (see
step 1) - inside the Jenkins container if using approach A above, or on the
dedicated build agent if using B.

## What the pipeline actually does

See the `Jenkinsfile` itself for the authoritative version; summary:

1. **Load version pins** from `docker/versions.env` - fails fast if the
   values there and in `docker-compose.yml`/`docker/Dockerfile`/`.env.example`
   have drifted (`scripts/check-versions.sh`).
2. **Build** the image, tagged both `sha-<git-short-sha>` (always unique,
   traceable to a commit) and `<hylafax-package-version>`.
3. **Smoke test** (`tests/smoke-test.sh`): boots the just-built image with a
   fake IAX2 modem, waits for Docker's own `HEALTHCHECK` to pass, exercises
   the hfaxd protocol (anonymous + authenticated login), confirms `faxstat`
   reports the modem idle, and confirms shutdown is fast and clean. This is
   the actual gate - a build that fails this never reaches "Push".
4. **Vulnerability scan** (Trivy) and **SBOM** (Syft, CycloneDX JSON,
   archived as a Jenkins build artifact) - both degrade to a loud warning
   rather than a silent skip if the tools aren't on the agent.
5. **Push** both tags to the Forgejo registry, plus `:latest` on
   `main`/`master` builds only. Controlled by the `PUSH` job parameter (set
   `false` for a build-only dry run, e.g. on a feature branch).
