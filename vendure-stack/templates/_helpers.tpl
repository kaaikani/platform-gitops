{{/*
Expand the name of the chart.
*/}}
{{- define "vendure-stack.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "vendure-stack.fullname" -}}
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
Create chart name and version as used by the chart label.
*/}}
{{- define "vendure-stack.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "vendure-stack.labels" -}}
helm.sh/chart: {{ include "vendure-stack.chart" . }}
{{ include "vendure-stack.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "vendure-stack.selectorLabels" -}}
app.kubernetes.io/name: {{ include "vendure-stack.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "vendure-stack.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "vendure-stack.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Vendure specific labels
*/}}
{{- define "vendure-stack.vendure.labels" -}}
{{ include "vendure-stack.labels" . }}
app.kubernetes.io/component: vendure
{{- end }}

{{/*
Vendure selector labels
*/}}
{{- define "vendure-stack.vendure.selectorLabels" -}}
{{ include "vendure-stack.selectorLabels" . }}
app.kubernetes.io/component: vendure
{{- end }}

{{/*
MySQL host - Uses FQDN if useFQDN is enabled, otherwise short name
*/}}
{{- define "vendure-stack.mysql.host" -}}
{{- if .Values.mysql.enabled }}
  {{- if .Values.vendure.useFQDN }}
    {{- printf "%s-mysql.%s.svc.cluster.local" .Release.Name .Release.Namespace }}
  {{- else }}
    {{- printf "%s-mysql" .Release.Name }}
  {{- end }}
{{- else if .Values.externalDatabase }}
{{- .Values.externalDatabase.host }}
{{- else }}
{{- .Values.vendure.database.host }}
{{- end }}
{{- end }}

{{/*
MySQL port
*/}}
{{- define "vendure-stack.mysql.port" -}}
{{- if .Values.externalDatabase }}
{{- .Values.externalDatabase.port | default 3306 }}
{{- else }}
{{- .Values.vendure.database.port | default 3306 }}
{{- end }}
{{- end }}

{{/*
MySQL database name
*/}}
{{- define "vendure-stack.mysql.database" -}}
{{- if .Values.externalDatabase }}
{{- .Values.externalDatabase.database | default "vendure" }}
{{- else }}
{{- .Values.vendure.database.name | default "vendure" }}
{{- end }}
{{- end }}

{{/*
Redis host - Uses FQDN if useFQDN is enabled, otherwise short name
*/}}
{{- define "vendure-stack.redis.host" -}}
{{- if .Values.redis.enabled }}
  {{- if .Values.vendure.useFQDN }}
    {{- printf "%s-redis-master.%s.svc.cluster.local" .Release.Name .Release.Namespace }}
  {{- else }}
    {{- printf "%s-redis-master" .Release.Name }}
  {{- end }}
{{- else if .Values.externalRedis }}
{{- .Values.externalRedis.host }}
{{- else }}
{{- .Values.vendure.redis.host }}
{{- end }}
{{- end }}

{{/*
Redis port
*/}}
{{- define "vendure-stack.redis.port" -}}
{{- if .Values.externalRedis }}
{{- .Values.externalRedis.port | default 6379 }}
{{- else }}
{{- .Values.vendure.redis.port | default 6379 }}
{{- end }}
{{- end }}

{{/*
Secret name
*/}}
{{- define "vendure-stack.secretName" -}}
{{- if .Values.secrets.existingSecret }}
{{- .Values.secrets.existingSecret }}
{{- else }}
{{- include "vendure-stack.fullname" . }}-secrets
{{- end }}
{{- end }}
