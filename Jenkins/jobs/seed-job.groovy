// Single source of truth for both Jenkins jobs. Applied two ways (same file,
// no copy-paste duplication to drift out of sync):
//   1. Automatically via JCasC's `jobs: - script: !include jobs/seed-job.groovy`
//      (see jcasc/jenkins.yaml) - runs once when the controller boots/reloads config.
//   2. On demand, idempotently, via `scripts/create-jobs.sh` (Jenkins CLI `groovy =`)
//      - safe to re-run any time; Job DSL updates existing jobs in place rather
//      than erroring if they already exist.
//
// GIT_REPO_URL is deliberately not a secret - the repo is public. If it were
// private, the credentialsId below would reference a Jenkins credential
// (see credentials/credentials.example.yaml), never a literal token.
//
// application-ci is a plain Pipeline job (not Multibranch) tracking `main`
// directly: a MultibranchPipelineJob's `branchSources { github { ... } }`
// triggers a synchronous branch-indexing scan against the GitHub API right
// at job-creation time, which reliably hung for tens of seconds inside this
// specific environment/plugin-version combination while standing this up -
// documented in the README as a real trade-off. A single-branch job with an
// explicit `githubPush()` trigger gets the same real, webhook-triggered
// behavior this project actually needs, without that hang.

def GIT_REPO_URL = 'https://github.com/davidso73/Devops-Project.git'

pipelineJob('application-ci') {
    displayName('application-ci')
    description('CI: test, lint, build, scan, tag, and push images. Never deploys.')
    definition {
        cpsScm {
            scm {
                git {
                    remote { url(GIT_REPO_URL) }
                    branch('main')
                }
            }
            scriptPath('Jenkins/Jenkinsfile-ci')
        }
    }
    triggers {
        githubPush()                // real webhook trigger
        pollSCM {
            scmpoll_spec('H/1 * * * *')   // 1-minute SCM-poll fallback if the webhook is ever unreachable
        }
    }
    properties {
        githubProjectUrl('https://github.com/davidso73/Devops-Project/')
    }
}

pipelineJob('application-cd') {
    displayName('application-cd')
    description('CD: deploy an already-built, already-pushed image tag to k8s. Never builds images.')
    parameters {
        stringParam('IMAGE_TAG', '', 'Commit-SHA tag produced by application-ci. "latest" is rejected.')
        stringParam('TARGET_NAMESPACE', 'devops-app', 'Destination namespace - must be on the allow-list in Jenkinsfile-cd.')
        stringParam('CI_BUILD_NUMBER', '', 'application-ci build number that produced IMAGE_TAG, for traceability.')
        stringParam('GIT_COMMIT_SHA', '', 'Git commit SHA that produced IMAGE_TAG, for traceability.')
    }
    definition {
        cpsScm {
            scm {
                git {
                    remote { url(GIT_REPO_URL) }
                    branch('main')
                }
            }
            scriptPath('Jenkins/Jenkinsfile-cd')
        }
    }
    properties {
        disableConcurrentBuilds()
    }
}
