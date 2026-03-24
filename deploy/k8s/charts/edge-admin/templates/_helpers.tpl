{{- /* deploy/k8s/charts/edge-admin/templates/_helpers.tpl */ -}}
{{/*
Expand the name of the chart.
*/}}
{{- define "edge-admin.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "edge-admin.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart label.
*/}}
{{- define "edge-admin.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels.
*/}}
{{- define "edge-admin.labels" -}}
helm.sh/chart: {{ include "edge-admin.chart" . }}
{{ include "edge-admin.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels.
*/}}
{{- define "edge-admin.selectorLabels" -}}
app.kubernetes.io/name: {{ include "edge-admin.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Name of the Secret to use (existing or chart-managed).
*/}}
{{- define "edge-admin.secretName" -}}
{{- if .Values.secrets.existingSecret }}
{{- .Values.secrets.existingSecret }}
{{- else }}
{{- include "edge-admin.fullname" . }}-secret
{{- end }}
{{- end }}

{{/*
Whether to render as StatefulSet.
*/}}
{{- define "edge-admin.isStatefulSet" -}}
{{- eq .Values.workload.kind "StatefulSet" }}
{{- end }}
