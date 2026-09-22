// hylafax+ Docker image: build -> verify -> smoke test -> scan -> SBOM -> push.
//
// Requires (see docs/JENKINS.md for full setup):
//   - A Jenkins agent with the `docker` CLI and access to a Docker daemon
//     (socket-mounted or DooD; this Jenkinsfile does not use DinD).
//   - Credential REGISTRY_CREDENTIALS_ID (username+token) for the Forgejo
//     container registry, added in Jenkins > Manage Jenkins > Credentials.
//   - Optional: `trivy` and `syft` on the agent for the scan/SBOM stages.
//     Both stages degrade to a skipped, clearly-logged warning if the tool
//     isn't installed, rather than failing the whole pipeline - see
//     docs/JENKINS.md for how to add them instead of silently trusting an
//     unscanned image.
pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '30'))
        ansiColor('xterm')
    }

    parameters {
        string(name: 'REGISTRY', defaultValue: '[redacted]', description: 'Container registry host')
        string(name: 'IMAGE_NAMESPACE', defaultValue: 'CHANGE_ME', description: 'Forgejo owner/org the image is pushed under')
        booleanParam(name: 'PUSH', defaultValue: true, description: 'Push to the registry (disable for a build-only dry run)')
        booleanParam(name: 'FAIL_ON_CRITICAL_CVE', defaultValue: true, description: 'Fail the build if Trivy finds a CRITICAL, fixable vulnerability')
    }

    environment {
        REGISTRY_CREDENTIALS_ID = 'forgejo-registry'
    }

    stages {
        stage('Load version pins') {
            steps {
                script {
                    def props = readProperties file: 'docker/versions.env'
                    env.HYLAFAX_PKG_VERSION = props.HYLAFAX_PKG_VERSION
                    env.IMAGE_NAME          = props.IMAGE_NAME
                    env.GIT_SHORT_SHA       = sh(script: 'git rev-parse --short=12 HEAD', returnStdout: true).trim()
                    env.IMAGE_REF           = "${params.REGISTRY}/${params.IMAGE_NAMESPACE}/${env.IMAGE_NAME}"
                    env.TAG_SHA             = "${env.IMAGE_REF}:sha-${env.GIT_SHORT_SHA}"
                    env.TAG_VERSION         = "${env.IMAGE_REF}:${env.HYLAFAX_PKG_VERSION}"
                    env.TAG_LATEST          = "${env.IMAGE_REF}:latest"
                }
                echo "Building ${env.TAG_SHA} (hylafax+ ${env.HYLAFAX_PKG_VERSION}, branch ${env.BRANCH_NAME ?: 'n/a'})"
            }
        }

        stage('Verify') {
            steps {
                sh 'chmod +x scripts/check-versions.sh tests/smoke-test.sh docker/entrypoint.sh docker/healthcheck.sh'
                sh './scripts/check-versions.sh'
                sh '''
                    if command -v hadolint >/dev/null 2>&1; then
                        hadolint docker/Dockerfile
                    else
                        echo "hadolint not installed on this agent - skipping Dockerfile lint (see docs/JENKINS.md)"
                    fi
                '''
            }
        }

        stage('Build') {
            steps {
                sh """
                    docker build \
                        --file docker/Dockerfile \
                        --tag ${env.TAG_SHA} \
                        --tag ${env.TAG_VERSION} \
                        --label org.opencontainers.image.revision=${env.GIT_SHORT_SHA} \
                        --label org.opencontainers.image.version=${env.HYLAFAX_PKG_VERSION} \
                        .
                """
            }
        }

        stage('Smoke test') {
            steps {
                sh "IMAGE=${env.TAG_SHA} ./tests/smoke-test.sh"
            }
        }

        stage('Vulnerability scan') {
            steps {
                script {
                    def hasTrivy = sh(script: 'command -v trivy >/dev/null 2>&1', returnStatus: true) == 0
                    if (!hasTrivy) {
                        echo "WARNING: trivy not installed on this agent - image is being pushed UNSCANNED. See docs/JENKINS.md to add it."
                        return
                    }
                    sh "trivy image --format table --output trivy-report.txt ${env.TAG_SHA}"
                    archiveArtifacts artifacts: 'trivy-report.txt', allowEmptyArchive: true
                    if (params.FAIL_ON_CRITICAL_CVE) {
                        sh "trivy image --exit-code 1 --severity CRITICAL --ignore-unfixed ${env.TAG_SHA}"
                    }
                }
            }
        }

        stage('SBOM') {
            steps {
                script {
                    def hasSyft = sh(script: 'command -v syft >/dev/null 2>&1', returnStatus: true) == 0
                    if (!hasSyft) {
                        echo "WARNING: syft not installed on this agent - no SBOM will be published for this build. See docs/JENKINS.md to add it."
                        return
                    }
                    sh "syft ${env.TAG_SHA} -o cyclonedx-json=sbom-${env.GIT_SHORT_SHA}.cdx.json"
                    archiveArtifacts artifacts: "sbom-${env.GIT_SHORT_SHA}.cdx.json"
                }
            }
        }

        stage('Push') {
            when { expression { return params.PUSH } }
            steps {
                withCredentials([usernamePassword(credentialsId: env.REGISTRY_CREDENTIALS_ID,
                                                   usernameVariable: 'REG_USER',
                                                   passwordVariable: 'REG_TOKEN')]) {
                    sh '''
                        echo "$REG_TOKEN" | docker login "$REGISTRY" -u "$REG_USER" --password-stdin
                    '''
                }
                sh "docker push ${env.TAG_SHA}"
                sh "docker push ${env.TAG_VERSION}"
                script {
                    if (env.BRANCH_NAME == 'main' || env.BRANCH_NAME == 'master') {
                        sh "docker tag ${env.TAG_SHA} ${env.TAG_LATEST}"
                        sh "docker push ${env.TAG_LATEST}"
                    }
                }
            }
        }
    }

    post {
        always {
            sh """
                docker rmi ${env.TAG_SHA} ${env.TAG_VERSION} ${env.TAG_LATEST} 2>/dev/null || true
                docker logout ${params.REGISTRY} 2>/dev/null || true
            """
        }
    }
}
