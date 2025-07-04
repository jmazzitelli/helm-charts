{{/* vim: set filetype=mustache: */}}

{{/*
Create a default fully qualified instance name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
To simulate the way the operator works, use deployment.instance_name.
*/}}
{{- define "kiali-server.fullname" -}}
{{- .Values.deployment.instance_name | trunc 63 }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "kiali-server.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Determine if on OpenShift (when debugging the chart for OpenShift use-cases, set "simulateOpenShift")
*/}}
{{- define "kiali-server.isOpenShift" -}}
{{- .Values.isOpenShift | default (.Capabilities.APIVersions.Has "operator.openshift.io/v1") -}}
{{- end }}

{{/*
Identifies the log_level.
*/}}
{{- define "kiali-server.logLevel" -}}
{{- .Values.server.observability.logger.log_level -}}
{{- end }}

{{/*
Common labels
*/}}
{{- define "kiali-server.labels" -}}
{{- if .Values.deployment.extra_labels }}
{{ toYaml .Values.deployment.extra_labels }}
{{- end }}
helm.sh/chart: {{ include "kiali-server.chart" . }}
app: kiali
{{ include "kiali-server.selectorLabels" . }}
version: {{ .Values.deployment.version_label | default .Chart.AppVersion | quote }}
app.kubernetes.io/version: {{ .Values.deployment.version_label | default .Chart.AppVersion | quote }}
app.kubernetes.io/part-of: "kiali"
{{- end }}

{{/*
Selector labels
*/}}
{{- define "kiali-server.selectorLabels" -}}
app.kubernetes.io/name: kiali
app.kubernetes.io/instance: {{ include "kiali-server.fullname" . }}
{{- end }}

{{/*
Determine the default login token signing key.
*/}}
{{- define "kiali-server.login_token.signing_key" -}}
{{- if .Values.login_token.signing_key }}
  {{- .Values.login_token.signing_key }}
{{- else }}
  {{- randAlphaNum 32 }}
{{- end }}
{{- end }}

{{/*
Determine the default web root.
*/}}
{{- define "kiali-server.server.web_root" -}}
{{- if .Values.server.web_root  }}
  {{- if (eq .Values.server.web_root "/") }}
    {{- .Values.server.web_root }}
  {{- else }}
    {{- .Values.server.web_root | trimSuffix "/" }}
  {{- end }}
{{- else }}
  {{- if eq "true" (include "kiali-server.isOpenShift" .) }}
    {{- "/" }}
  {{- else }}
    {{- "/kiali" }}
  {{- end }}
{{- end }}
{{- end }}

{{/*
Determine the default identity cert file. There is no default if on k8s; only on OpenShift.
*/}}
{{- define "kiali-server.identity.cert_file" -}}
{{- if hasKey .Values.identity "cert_file" }}
  {{- .Values.identity.cert_file }}
{{- else }}
  {{- if eq "true" (include "kiali-server.isOpenShift" .) }}
    {{- "/kiali-cert/tls.crt" }}
  {{- else }}
    {{- "" }}
  {{- end }}
{{- end }}
{{- end }}

{{/*
Determine the default identity private key file. There is no default if on k8s; only on OpenShift.
*/}}
{{- define "kiali-server.identity.private_key_file" -}}
{{- if hasKey .Values.identity "private_key_file" }}
  {{- .Values.identity.private_key_file }}
{{- else }}
  {{- if eq "true" (include "kiali-server.isOpenShift" .) }}
    {{- "/kiali-cert/tls.key" }}
  {{- else }}
    {{- "" }}
  {{- end }}
{{- end }}
{{- end }}

{{/*
Determine the default deployment.ingress.enabled. Disable it on k8s; enable it on OpenShift.
*/}}
{{- define "kiali-server.deployment.ingress.enabled" -}}
{{- if hasKey .Values.deployment.ingress "enabled" }}
  {{- .Values.deployment.ingress.enabled }}
{{- else }}
  {{- if eq "true" (include "kiali-server.isOpenShift" .) }}
    {{- true }}
  {{- else }}
    {{- false }}
  {{- end }}
{{- end }}
{{- end }}

{{/*
Determine the istio namespace - default is where Kiali is installed.
*/}}
{{- define "kiali-server.istio_namespace" -}}
{{- if .Values.istio_namespace }}
  {{- .Values.istio_namespace }}
{{- else }}
  {{- .Release.Namespace }}
{{- end }}
{{- end }}

{{/*
Determine the auth strategy to use - default is "token" on Kubernetes and "openshift" on OpenShift.
*/}}
{{- define "kiali-server.auth.strategy" -}}
{{- if .Values.auth.strategy }}
  {{- if (and ((and (eq .Values.auth.strategy "openshift") (not .Values.kiali_route_url))) (not .Values.auth.openshift.redirect_uris)) }}
    {{- fail "You did not define what the Kiali Route URL will be (--set kiali_route_url=...). Without this set, the openshift auth strategy will not work. Either (a) set that, (b) explicitly define redirect URIs via --set auth.openshift.redirect_uris, or (c) use a different auth strategy via the --set auth.strategy=... option." }}
  {{- end }}
  {{- .Values.auth.strategy }}
{{- else }}
  {{- if eq "true" (include "kiali-server.isOpenShift" .) }}
    {{- if (and (not .Values.kiali_route_url) (not .Values.auth.openshift.redirect_uris)) }}
      {{- fail "You did not define what the Kiali Route URL will be (--set kiali_route_url=...). Without this set, the openshift auth strategy will not work. Either (a) set that, (b) explicitly define redirect URIs via --set auth.openshift.redirect_uris, or (c) use a different auth strategy via the --set auth.strategy=... option." }}
    {{- end }}
    {{- "openshift" }}
  {{- else }}
    {{- "token" }}
  {{- end }}
{{- end }}
{{- end }}

{{/*
Determine the root namespace - default is where Kiali is installed.
*/}}
{{- define "kiali-server.external_services.istio.root_namespace" -}}
{{- if .Values.external_services.istio.root_namespace }}
  {{- .Values.external_services.istio.root_namespace }}
{{- else }}
  {{- .Release.Namespace }}
{{- end }}
{{- end }}

{{/*
Autodetect remote cluster secrets if enabled - looks for secrets in the same namespace where Kiali is installed.
Note that this will ignore any secret named "kiali-multi-cluster-secret" because that will optionally be mounted always.
Returns a JSON dict whose keys are the cluster names and values are the cluster secret data.
*/}}
{{- define "kiali-server.remote-cluster-secrets" -}}
{{- $theDict := dict }}
{{- if .Values.clustering.autodetect_secrets.enabled }}
  {{- $secretLabelToLookFor := (regexSplit "=" .Values.clustering.autodetect_secrets.label 2) }}
  {{- $secretLabelNameToLookFor := first $secretLabelToLookFor }}
  {{- $secretLabelValueToLookFor := last $secretLabelToLookFor }}
  {{- range $i, $secret := (lookup "v1" "Secret" .Release.Namespace "").items }}
    {{- if ne $secret.metadata.name "kiali-multi-cluster-secret" }}
      {{- if (and (and (hasKey $secret.metadata "labels") (hasKey $secret.metadata.labels $secretLabelNameToLookFor)) (eq (get $secret.metadata.labels $secretLabelNameToLookFor) ($secretLabelValueToLookFor))) }}
        {{- $clusterName := $secret.metadata.name }}
        {{- if (and (hasKey $secret.metadata "annotations") (hasKey $secret.metadata.annotations "kiali.io/cluster")) }}
          {{- $clusterName = get $secret.metadata.annotations "kiali.io/cluster" }}
        {{- end }}
        {{- $theDict = set $theDict $clusterName $secret.metadata.name }}
      {{- end }}
    {{- end }}
  {{- end }}
{{- end }}
{{- $theDict | toJson }}
{{- end }}

{{/*
Returns true if the given resource kind is in .Values.skipResources
This aborts if .Values.skipResources has invalid values.
*/}}
{{- define "kiali-server.isSkippedResource" -}}
  {{- $validSkipResources := dict "clusterrole" true "clusterrolebinding" true "sa" true }}
  {{- $ctx := .ctx }}
  {{- $name := .name }}
  {{- range $i, $item := $ctx.Values.skipResources }}
    {{- if not (hasKey $validSkipResources $item) }}
      {{- fail (printf "Aborting due to an invalid entry [%q] in skipResources: %q. Valid list item values are: %q" $item $ctx.Values.skipResources (keys $validSkipResources)) }}
    {{- end }}
  {{- end }}
  {{- has $name $ctx.Values.skipResources }}
{{- end }}
