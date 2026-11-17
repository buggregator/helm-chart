{{/*
Expand the name of the chart.
*/}}
{{- define "buggregator.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "buggregator.fullname" -}}
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
{{- define "buggregator.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "buggregator.labels" -}}
helm.sh/chart: {{ include "buggregator.chart" . }}
{{ include "buggregator.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "buggregator.selectorLabels" -}}
app.kubernetes.io/name: {{ include "buggregator.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "buggregator.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "buggregator.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Secret name for auth credentials
*/}}
{{- define "buggregator.authSecretName" -}}
{{- if .Values.auth.existingSecret }}
{{- .Values.auth.existingSecret }}
{{- else }}
{{- printf "%s-auth" (include "buggregator.fullname" .) }}
{{- end }}
{{- end }}

{{/*
SQLite DSN: the explicit value, else a file on the volume, else memory.
*/}}
{{- define "buggregator.databaseDsn" -}}
{{- if .Values.database.dsn }}
{{- .Values.database.dsn }}
{{- else if .Values.storage.enabled }}
{{- "/data/buggregator.db" }}
{{- else }}
{{- ":memory:" }}
{{- end }}
{{- end }}

{{/*
Attachment storage mode: the explicit value, else filesystem on the volume, else memory.
*/}}
{{- define "buggregator.attachmentMode" -}}
{{- if .Values.attachmentStorage.mode }}
{{- .Values.attachmentStorage.mode }}
{{- else if .Values.storage.enabled }}
{{- "filesystem" }}
{{- else }}
{{- "memory" }}
{{- end }}
{{- end }}

{{/*
JWT secret: the explicit value, else the one already stored in the release's
secret (so sessions survive helm upgrade), else a new random one.
*/}}
{{- define "buggregator.jwtSecret" -}}
{{- if .Values.auth.jwtSecret }}
{{- .Values.auth.jwtSecret | b64enc }}
{{- else }}
{{- $existing := lookup "v1" "Secret" .Release.Namespace (printf "%s-auth" (include "buggregator.fullname" .)) }}
{{- if and $existing (index ($existing.data | default dict) "jwt-secret") }}
{{- index $existing.data "jwt-secret" }}
{{- else }}
{{- randAlphaNum 64 | b64enc }}
{{- end }}
{{- end }}
{{- end }}
