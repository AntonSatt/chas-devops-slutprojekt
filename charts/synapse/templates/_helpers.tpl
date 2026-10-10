{{/*
Gemensamma bitar som alla templates använder. Filer som börjar med _ blir
inga Kubernetes-objekt, bara definitioner som hämtas med include.
*/}}

{{/*
Namnet på alla objekt. Heter releasen redan något med "synapse" används
releasenamnet rakt av, annars release-synapse. Max 63 tecken, som är
gränsen för namn i Kubernetes.
*/}}
{{- define "synapse.fullname" -}}
{{- if contains .Chart.Name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
Labels som sitter på alla objekt. Standardnamnen gör att verktyg som Argo CD
och Grafana förstår vad som hör ihop.
*/}}
{{- define "synapse.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
Labels som en Service eller Deployment väljer poddar med. De får aldrig
ändras efter install, för selector i en Deployment går inte att byta.
Därför finns ingen version här. component skiljer Synapse, Element och
Postgres åt, annars skulle Synapse-servicen även skicka trafik till
Postgres-podden.

Anropas med en dict: include "synapse.selectorLabels" (dict "ctx" . "component" "postgres")
*/}}
{{- define "synapse.selectorLabels" -}}
app.kubernetes.io/name: {{ .ctx.Chart.Name }}
app.kubernetes.io/instance: {{ .ctx.Release.Name }}
app.kubernetes.io/component: {{ .component }}
{{- end -}}

{{/*
Postgres-servicens namn. Synapse ansluter till det, så det behövs på två
ställen.
*/}}
{{- define "synapse.postgresHost" -}}
{{- printf "%s-postgres" (include "synapse.fullname" .) -}}
{{- end -}}
