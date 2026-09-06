{{/*
Common labels applied to every resource this chart creates.
*/}}
{{- define "vmapp.labels" -}}
app.kubernetes.io/part-of: vmapp
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}

{{/*
Selector labels for a given component (frontend/backend/worker).
*/}}
{{- define "vmapp.selectorLabels" -}}
app.kubernetes.io/name: vmapp-{{ . }}
app.kubernetes.io/part-of: vmapp
{{- end -}}
