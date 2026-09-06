# CI agent: builds/tests/lints/scans/pushes. No docker.sock anywhere - image
# builds run via BuildKit in rootless mode (see README "Agent and container
# security" for why this option was chosen over buildah/DinD). Workspace is
# an emptyDir - gone the moment the pod is deleted at the end of the build,
# per "temporary workspace, no persistent cache containing secrets."
apiVersion: v1
kind: Pod
metadata:
  labels:
    role: ci-agent
spec:
  serviceAccountName: jenkins-ci-agent
  automountServiceAccountToken: true
  containers:
    - name: buildkit
      image: moby/buildkit:v0.17.1-rootless
      imagePullPolicy: IfNotPresent
      # No command/args override: the image's own entrypoint starts
      # `buildkitd` in rootless mode, listening on its default local socket -
      # Jenkins execs `buildctl` calls into this already-running container
      # per build step, it doesn't need to be the "cat/sleep" placeholder
      # pattern the other containers use.
      env:
        - name: BUILDKITD_FLAGS
          value: "--oci-worker-no-process-sandbox"
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
        # Rootless BuildKit creates a user namespace (unshare) to build
        # images without a privileged daemon or docker.sock - the default
        # seccomp profile blocks that syscall. This is the one, documented,
        # minimal exception to "seccomp RuntimeDefault everywhere" in this
        # project, made specifically (and only) for this container, for
        # exactly this reason - not a blanket relaxation.
        seccompProfile:
          type: Unconfined
      resources:
        requests: { cpu: "300m", memory: "512Mi" }
        limits: { cpu: "1", memory: "1Gi" }
      volumeMounts:
        - name: workspace-volume
          mountPath: /home/jenkins/agent
        - name: buildkit-cache
          mountPath: /home/user/.local/share/buildkit
    - name: tools
      image: 832767338129.dkr.ecr.il-central-1.amazonaws.com/vmapp-ci-tools:v1.0.0
      imagePullPolicy: IfNotPresent
      command: ["sleep"]
      args: ["99d"]
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: false
        capabilities:
          drop: ["ALL"]
        seccompProfile:
          type: RuntimeDefault
      resources:
        requests: { cpu: "200m", memory: "256Mi" }
        limits: { cpu: "500m", memory: "512Mi" }
      volumeMounts:
        - name: workspace-volume
          mountPath: /home/jenkins/agent
  volumes:
    - name: workspace-volume
      emptyDir: {}
    - name: buildkit-cache
      emptyDir: {}
