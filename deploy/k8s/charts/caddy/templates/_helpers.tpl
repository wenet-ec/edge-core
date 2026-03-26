{{- /* deploy/k8s/charts/caddy/templates/_helpers.tpl */ -}}
{{- define "caddy.labels" -}}
app.kubernetes.io/name: caddy
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: caddy-{{ .Chart.Version }}
{{- end }}

{{- define "caddy.selectorLabels" -}}
app.kubernetes.io/name: caddy
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
