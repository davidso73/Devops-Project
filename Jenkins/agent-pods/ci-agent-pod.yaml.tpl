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
    # Overrides the Kubernetes plugin's implicit "jnlp" agent-connection
    # container (default request 100m/256Mi) with a smaller one - this
    # 2-node, t3.small (~1.4Gi allocatable per node) free-tier cluster
    # doesn't have room for the plugin's default on top of buildkit+tools
    # (see README "Trade-offs" - node capacity).
    - name: jnlp
      resources:
        requests: { cpu: "50m", memory: "96Mi" }
        limits: { cpu: "200m", memory: "192Mi" }
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
        # Rootless BuildKit's rootlesskit wrapper builds its own user
        # namespace by invoking newuidmap/newgidmap, which are setuid-root
        # binaries inside the image - allowPrivilegeEscalation: false sets
        # the kernel's no_new_privs, which disables setuid entirely and
        # makes those calls fail outright ("operation not permitted"),
        # confirmed live: buildctl builds never started at all without this.
        # This container structurally cannot build container images without
        # some privilege-escalation path; rootless BuildKit's is the
        # narrowest one available (no docker.sock, no privileged mode, no
        # host root) - see README "Agent and container security" for the
        # comparison against buildah/DinD that led to this choice anyway.
        allowPrivilegeEscalation: true
        # newuidmap/newgidmap are setuid-root, but a dropped-to-empty
        # capability bounding set blocks a setuid binary from gaining a
        # capability on exec even with allowPrivilegeEscalation: true (the
        # kernel intersects the binary's capabilities with the process's
        # bounding set) - confirmed live: the same "operation not permitted"
        # persisted with allowPrivilegeEscalation: true alone until SETUID/
        # SETGID were added back here.
        #
        # SYS_ADMIN is also required, confirmed live by a second failure one
        # layer in: rootlesskit's own unshare(CLONE_NEWUSER) succeeds with
        # just SETUID/SETGID (buildkitd itself starts fine), but each `RUN`
        # step's nested runc process needs to mount its own /proc, which
        # needs CAP_SYS_ADMIN - and a capability the bounding set excludes
        # is unavailable even to "root" inside a freshly created user
        # namespace (the namespace grants a full capability set *within
        # itself*, but that grant is still capped by the inherited bounding
        # set). This capability's blast radius stays confined to this one
        # container's own user+mount namespace - it is not host-level
        # SYS_ADMIN - but it is the real, necessary cost of rootless image
        # builds under a bounding-set-restricted pod, documented here rather
        # than glossed over. Every OTHER container in this project keeps a
        # fully empty, unmodified capability set.
        capabilities:
          add: ["SETUID", "SETGID", "SYS_ADMIN"]
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
        requests: { cpu: "200m", memory: "300Mi" }
        limits: { cpu: "1", memory: "700Mi" }
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
        requests: { cpu: "100m", memory: "150Mi" }
        limits: { cpu: "500m", memory: "350Mi" }
      volumeMounts:
        - name: workspace-volume
          mountPath: /home/jenkins/agent
  volumes:
    - name: workspace-volume
      emptyDir: {}
    - name: buildkit-cache
      emptyDir: {}
