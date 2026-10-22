{{/*
Chartets namn.
*/}}
{{- define "gitea.name" -}}
{{- .Chart.Name }}
{{- end }}

{{/*
Namnet på resurserna. Heter releasen redan något med "gitea" används den
rakt av, så det inte blir gitea-gitea. Kortas till 63 tecken, gränsen för
namn i Kubernetes.
*/}}
{{- define "gitea.fullname" -}}
{{- if contains .Chart.Name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
Chart och version, för helm.sh/chart-labeln.
*/}}
{{- define "gitea.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Standardlabels på alla resurser.
*/}}
{{- define "gitea.labels" -}}
helm.sh/chart: {{ include "gitea.chart" . }}
{{ include "gitea.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Labels som Service och Deployment väljer poddar med. Får inte ändras efter
första installationen: en Deployments selector går inte att ändra.
*/}}
{{- define "gitea.selectorLabels" -}}
app.kubernetes.io/name: {{ include "gitea.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
