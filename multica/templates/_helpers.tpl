{{/*
Expand the name of the chart.
*/}}
{{- define "multica.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "multica.fullname" -}}
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
{{- define "multica.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "multica.labels" -}}
helm.sh/chart: {{ include "multica.chart" . }}
{{ include "multica.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.podLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "multica.selectorLabels" -}}
app.kubernetes.io/name: {{ include "multica.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Backend selector labels
*/}}
{{- define "multica.backend.selectorLabels" -}}
{{ include "multica.selectorLabels" . }}
app.kubernetes.io/component: backend
{{- end }}

{{/*
Frontend selector labels
*/}}
{{- define "multica.frontend.selectorLabels" -}}
{{ include "multica.selectorLabels" . }}
app.kubernetes.io/component: frontend
{{- end }}

{{/*
PostgreSQL selector labels
*/}}
{{- define "multica.postgresql.selectorLabels" -}}
{{ include "multica.selectorLabels" . }}
app.kubernetes.io/component: postgresql
{{- end }}

{{/*
Backend full name
*/}}
{{- define "multica.backend.fullname" -}}
{{ include "multica.fullname" . }}-backend
{{- end }}

{{/*
Frontend full name
*/}}
{{- define "multica.frontend.fullname" -}}
{{ include "multica.fullname" . }}-frontend
{{- end }}

{{/*
PostgreSQL full name
*/}}
{{- define "multica.postgresql.fullname" -}}
{{ include "multica.fullname" . }}-postgresql
{{- end }}

{{/*
ServiceAccount name
*/}}
{{- define "multica.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "multica.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Database URL
*/}}
{{- define "multica.databaseUrl" -}}
{{- if .Values.postgresql.enabled }}
{{- $user := .Values.postgresql.auth.username }}
{{- $pass := or .Values.postgresql.auth.password (include "multica.postgresqlPassword" .) }}
{{- $host := include "multica.postgresql.fullname" . }}
{{- $port := 5432 }}
{{- $db := .Values.postgresql.auth.database }}
{{- printf "postgres://%s:%s@%s:%d/%s?sslmode=disable" $user $pass $host $port $db }}
{{- else }}
{{- if .Values.externalDatabase.url }}
{{- .Values.externalDatabase.url }}
{{- else }}
{{- $user := .Values.externalDatabase.username }}
{{- $pass := .Values.externalDatabase.password }}
{{- $host := .Values.externalDatabase.host }}
{{- $port := .Values.externalDatabase.port | int }}
{{- $db := .Values.externalDatabase.database }}
{{- $sslmode := .Values.externalDatabase.sslmode }}
{{- printf "postgres://%s:%s@%s:%d/%s?sslmode=%s" $user $pass $host $port $db $sslmode }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Frontend origin URL
*/}}
{{- define "multica.frontendOrigin" -}}
{{- if .Values.frontend.origin }}
{{- .Values.frontend.origin }}
{{- else if .Values.ingress.enabled }}
{{- if .Values.ingress.separateHosts.enabled }}
{{- $host := .Values.ingress.separateHosts.frontendHost | required "ingress.separateHosts.frontendHost is required when separateHosts is enabled" }}
{{- if .Values.ingress.tls }}
{{- printf "https://%s" $host }}
{{- else }}
{{- printf "http://%s" $host }}
{{- end }}
{{- else }}
{{- $host := (index .Values.ingress.hosts 0).host }}
{{- if .Values.ingress.tls }}
{{- printf "https://%s" $host }}
{{- else }}
{{- printf "http://%s" $host }}
{{- end }}
{{- end }}
{{- else }}
{{- printf "http://localhost:3000" }}
{{- end }}
{{- end }}

{{/*
JWT secret
*/}}
{{- define "multica.jwtSecret" -}}
{{- if .Values.backend.jwtSecret }}
{{- .Values.backend.jwtSecret }}
{{- else }}
{{- randAlphaNum 32 }}
{{- end }}
{{- end }}

{{/*
PostgreSQL password
*/}}
{{- define "multica.postgresqlPassword" -}}
{{- if .Values.postgresql.auth.password }}
{{- .Values.postgresql.auth.password }}
{{- else }}
{{- randAlphaNum 16 }}
{{- end }}
{{- end }}

{{/*
Agent runtime full name
*/}}
{{- define "multica.agent.fullname" -}}
{{ include "multica.fullname" . }}-agent
{{- end }}
