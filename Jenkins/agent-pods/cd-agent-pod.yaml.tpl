# CD agent: kubectl + helm only. No docker.sock, no BuildKit, no build
# tooling at all - structurally incapable of building an image, matching
# "the CD is responsible for deploy, verification, and rollback, but cannot
# rebuild the image." Authenticates to the cluster via jenkins-cd-agent's
# projected ServiceAccount token (see rbac/cd-agent-rbac.yaml) - no
# kubeconfig file, no static credential.
apiVersion: v1
kind: Pod
metadata:
  labels:
    role: cd-agent
spec:
  serviceAccountName: jenkins-cd-agent
  automountServiceAccountToken: true
  containers:
    # See ci-agent-pod.yaml.tpl - same jnlp-container-size override, same
    # 2-node free-tier capacity reason.
    - name: jnlp
      resources:
        requests: { cpu: "50m", memory: "96Mi" }
        limits: { cpu: "200m", memory: "192Mi" }
    - name: deploy-tools
      image: 832767338129.dkr.ecr.il-central-1.amazonaws.com/vmapp-cd-tools:v1.0.0
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
        requests: { cpu: "150m", memory: "256Mi" }
        limits: { cpu: "500m", memory: "512Mi" }
      volumeMounts:
        - name: workspace-volume
          mountPath: /home/jenkins/agent
  volumes:
    - name: workspace-volume
      emptyDir: {}
