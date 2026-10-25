# Drift: prod-klustret

På labben står prod redan uppe, och uppgifterna görs mot det körande
klustret: titta, felsöka och ändra en del. Den här sidan är för det. Vill
du bygga ett eget kluster från noll, se [steg-för-steg-guiden](steg-for-steg.md).
Varför delarna är byggda som de är står i README och i `docs/`.

Kommandona är provade mot prod 2026-10-19. Står inget annat körs de från
repots rot.

## Regeln: titta live, ändra via git

- Argo CD läser `main` var tredje minut och har `selfHeal`. Ändrar du
  något med `kubectl apply`, `edit` eller `scale` backar Argo det.
- Varje merge till `main` kör pipelinen mot prod: Terraform ändrar bara det
  som skiljer, Ansible gör bara det som behövs, sedan synkar Argo resten.
- Okej att göra live: `get`, `describe`, `logs`, `exec`, `rollout restart`,
  ta bort en pod (Deploymenten gör en ny) och laga data i en databas.
- En ändring: gren, commit, MR, merge. Följ den med
  `kubectl -n argocd get applications -w`.

## Kom åt prod

### kubectl från din dator

Kubeconfigen ligger på första control planen. Med `.envrc` laddad:

```bash
CP0_IP=$(curl -s -H "Authorization: Bearer $HCLOUD_TOKEN" "https://api.hetzner.cloud/v1/servers?name=group1-node-cp-0" | jq -r '.servers[0].public_net.ipv4.ip')
(umask 077; ssh -i ~/.ssh/group1_hetzner root@"$CP0_IP" cat /etc/rancher/k3s/k3s.yaml \
  | sed -e "s/127.0.0.1/$CP0_IP/" -e 's/: default$/: group1-prod/' > group1.kubeconfig)
export KUBECONFIG=$PWD/group1.kubeconfig
kubectl config current-context
kubectl get nodes
```

Kontexten heter `group1-prod`. Filen är gitignorerad men är admin-nyckeln
till prod: skicka den aldrig i en kanal. Byggs prod om från noll får
klustret nya certifikat, och då hämtar du filen igen.

Har du andra kluster i `~/.kube/config` kan du lägga båda i `KUBECONFIG`
(`~/.kube/config:$PWD/group1.kubeconfig`) och byta med
`kubectl config use-context group1-prod`. Det gäller alla terminaler, så
kolla kontexten innan du ändrar något.

### SSH till noderna

```bash
ssh -i ~/.ssh/group1_hetzner root@"$CP0_IP"
WORKER_IP=$(awk '/ansible_host/ {sub("ansible_host=", "", $2); print $2}' ansible/inventory/worker.ini)
ssh -i ~/.ssh/group1_hetzner root@"$WORKER_IP"
```

`kubectl` fungerar som root på control planes. Användaren `group1` med
gruppnyckeln finns på alla noder, det är den läraren använder.

### Webbsidorna

| Vad | Hur | Inloggning |
|---|---|---|
| Grafana | https://grafana.group-1.doe25.chas-lab.dev | `admin`, lösenordet nedan |
| Element (Synapse) | https://element.group-1.doe25.chas-lab.dev | användare, se `charts/synapse/README.md` |
| Ghost | https://ghost.group-1.doe25.chas-lab.dev | admin på `/ghost` |
| Argo CD | `kubectl -n argocd port-forward svc/argocd-server 8080:80`, sedan http://localhost:8080 | `admin`, lösenordet nedan |
| Prometheus | `kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090` | ingen |
| Alertmanager | `kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-alertmanager 9093:9093` | ingen |

Prometheus och Alertmanager har ingen inloggning, därför har de ingen
ingress. Lösenorden går till urklipp i stället för till skärmen, så de syns
inte vid skärmdelning och hamnar inte i terminalloggar. På Wayland byter du
`xclip -selection clipboard` mot `wl-copy`.

```bash
kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d | xclip -selection clipboard
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d | xclip -selection clipboard
```

## Hälsokoll på en minut

```bash
kubectl get nodes
kubectl -n argocd get applications
kubectl get pods -A | grep -v -E 'Running|Completed'
kubectl -n traefik get certificate
PROM=/api/v1/namespaces/monitoring/services/monitoring-kube-prometheus-prometheus:9090/proxy
kubectl get --raw "$PROM/api/v1/alerts" | jq -r '.data.alerts[] | select(.state=="firing") | "\(.labels.alertname) \(.labels.namespace // "")"'
curl -s -o /dev/null -w '%{http_code}\n' https://grafana.group-1.doe25.chas-lab.dev/login
```

| Kommando | Friskt |
|---|---|
| `get nodes` | fyra noder `Ready`: `group1-node-cp-0..2` och `group1-worker` |
| `get applications` | alla `Synced` och `Healthy` |
| `get pods ... grep -v` | bara rubrikraden. En rad med `CrashLoopBackOff` eller `Pending` är ett fel |
| `get certificate` | `wildcard-group-1` med `READY True` |
| larmen | bara `Watchdog`, som alltid brinner som bevis på att kedjan lever |
| `curl` | `200` |

`kubectl get --raw` frågar Prometheus genom Kubernetes API, utan
port-forward. Samma sätt fungerar för PromQL, till exempel targets som är
nere: `kubectl get --raw "$PROM/api/v1/query?query=up%3D%3D0" | jq '.data.result'`.

## Delarna

| Del | Titta | Ändra i | Mer |
|---|---|---|---|
| Kluster och noder | `kubectl get nodes -o wide`, taint: `kubectl get nodes -o custom-columns=NOD:.metadata.name,TAINT:.spec.taints[*].effect` | `terraform/`, `ansible/` | README *Terraform*, *Ansible* |
| Brandväggar | Hetzner Console, `ufw status` på workern | `terraform/main.tf` (control planes), `ansible/roles/k3s_agent/tasks/main.yml` (workern) | README *Ansible* |
| DNS | `dig +short grafana.group-1.doe25.chas-lab.dev` ska ge workerns adress | `dns/main.tf`, egen state | README *DNS* |
| Cert och HTTPS | `kubectl -n traefik get certificate`, `kubectl get certificaterequest,order,challenge -A` | `kubernetes/manifests/cert-manager-issuers/`, `kubernetes/apps/templates/traefik.yaml` | README *Ingress och HTTPS* |
| Ingresser | `kubectl get ingress -A` | hostnamnen i `kubernetes/values/` | |
| Argo CD | `kubectl -n argocd get applications`, revisionen: `kubectl -n argocd get application root -o jsonpath='{.status.sync.revision}'` | `kubernetes/apps/templates/`, en fil per app | [argo-cd.md](gitops/argo-cd.md) |
| Monitoring | Prometheus *Status > Targets*, Grafana *Dashboards* | `kubernetes/values/monitoring.yaml` | [monitoring.md](monitoring/monitoring.md) |
| Larm | Prometheus *Alerts*, Alertmanager, Mattermost | `alertmanager` i `kubernetes/values/monitoring.yaml`, `kubernetes/manifests/larmtest/` | [larm.md](monitoring/larm.md) |
| Loggar | Grafana *Explore*, datasourcen `Loki`: `{namespace="ghost"}`, `{job="journal"}` | `kubernetes/values/loki.yaml`, `kubernetes/values/alloy.yaml` | [loggar.md](loggar/loggar.md) |
| Secrets | bara namnen: `kubectl get secret -A`. Skriv aldrig ut ett värde i onödan | CI-variabeln och `ansible/roles/app_secrets/` | README *CI-variabler* |
| Pipelinen | GitLab, *Build > Pipelines* | `.gitlab-ci.yml`, `ci/util.Dockerfile` | |
| Synapse | `kubectl -n synapse get pods`, `curl -s https://matrix.group-1.doe25.chas-lab.dev/_matrix/client/versions` | `kubernetes/values/synapse.yaml`, `charts/synapse/` | [README](../charts/synapse/README.md) |
| Ghost | `kubectl -n ghost get pods` | `kubernetes/values/ghost.yaml`, `charts/ghost/` | README *Ghost* |

## Vill du ändra

| Ändring | Var | Så ser du att det gick igenom |
|---|---|---|
| VM-typ på control planes | `server_type` i `terraform/main.tf` | `terraform-deploy` i pipelinen. Servrarna byter typ på plats och startas om, prova i dev först |
| Antal control planes | `control_plane_count` i `terraform/variables.tf` | `kubectl get nodes`. Håll det udda (1 eller 3), etcd behöver majoritet |
| k3s-version | `k3s_version` i `ansible/group_vars/all.yml` | Gäller bara nya noder: installationen hoppas över när k3s redan finns (`creates:`) |
| En port | `terraform/main.tf` (control planes), `ansible/roles/k3s_agent/tasks/main.yml` (workern) | `ufw status` på workern, brandväggen i Hetzner |
| En ny adress | bara ingressens host, wildcard-posten och wildcard-certet täcker alla namn under `group-1` | `kubectl get ingress -A` |
| Grafanas adress | `grafana.ingress.hosts` och `root_url` i `kubernetes/values/monitoring.yaml` | `kubectl -n monitoring get ingress` |
| Hur länge metrics sparas | `retention` i `kubernetes/values/monitoring.yaml` | `kubectl -n monitoring get prometheus -o jsonpath='{.items[0].spec.retention}'` |
| En ny larmregel | en PrometheusRule bredvid appen, mönster i `kubernetes/manifests/larmtest/prometheusrule.yaml` | Prometheus *Alerts* |
| Vilka larm som når Mattermost | `alertmanager.config.route` i `kubernetes/values/monitoring.yaml` | Alertmanager *Status* |
| Larmtestet på eller av | `replicas` i `kubernetes/manifests/larmtest/deployment.yaml` | `LARM` i Mattermost efter någon minut, `OK` när det är av |
| Fler Element-poddar | `element.replicas` i `kubernetes/values/synapse.yaml` (2 i charten) | `kubectl -n synapse get pods` |
| En ny app | en fil i `kubernetes/apps/templates/`, values i `kubernetes/values/` | `kubectl -n argocd get applications` |
| Rotera en secret | CI-variabeln, kör pipelinen (rollen `app_secrets`), sedan `kubectl -n NS rollout restart deployment` | Databaslösenord sätts bara när databasen skapas: byt det i databasen också, annars kommer appen inte in |
| Förnya certet | `kubectl -n traefik delete secret wildcard-group-1-tls`, cert-manager hämtar ett nytt | `kubectl -n traefik get certificate`. Let's Encrypt ger max fem likadana cert i veckan, gör det inte i onödan |

## Felsökning

### En pod kraschar (`CrashLoopBackOff`)

```bash
NS=ghost
kubectl -n "$NS" get pods
POD=$(kubectl -n "$NS" get pods --no-headers | awk '/CrashLoopBackOff/ {print "pod/" $1; exit}')
kubectl -n "$NS" logs "$POD" --previous --tail=30
kubectl -n "$NS" describe "$POD"
```

Raden med `POD=` tar den första podden som kraschar. `--previous` visar
loggen från containern som dog, det är där felet står.
I `describe`: *Last State* (`OOMKilled` är minnet, `Error` är appen själv)
och *Events* längst ned (`Liveness probe failed`).

Hänt 2026-10-19: Ghost gav `MigrationsAreLockedError`. Liveness-proben dödade
Ghost mitt i första migreringen av databasen, och låset i tabellen
`migrations_lock` släpptes aldrig. Varje ny start såg låset och gav upp.

### En pod står `Pending`

`kubectl -n "$NS" describe "$POD"` och läs *Events*. `untolerated taint`
betyder att den bara får plats på en control plane och saknar toleration.
`Insufficient cpu` eller `memory` betyder att workern är full. En
`PersistentVolumeClaim` som inte är `Bound` betyder att disken saknas.

### En adress svarar inte

Följ vägen in, utifrån och in:

| Steg | Kommando | Fel här betyder |
|---|---|---|
| DNS | `dig +short ghost.group-1.doe25.chas-lab.dev` | fel eller ingen adress: `dns/` |
| Traefik | `kubectl -n traefik get pods,svc` | inget svarar alls |
| Ingress | `kubectl get ingress -A` | `404`: Traefik har ingen regel för hosten eller sökvägen |
| Poddarna bakom | `kubectl -n ghost get endpointslices -l kubernetes.io/service-name=ghost-ghost-chart -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]} ready={.conditions.ready}{"\n"}{end}'` | `503`: regeln finns men ingen pod är `ready` |
| Certet | `kubectl -n traefik get certificate` | certvarning i webbläsaren |

### En Argo-app är `OutOfSync` eller `Degraded`

```bash
APP=ghost
kubectl -n argocd get application "$APP" -o jsonpath='{.status.sync.status} {.status.health.status} {.status.operationState.message}{"\n"}'
```

`OutOfSync` betyder att klustret inte är som git, och meddelandet säger
oftast varför synken föll. `Degraded` betyder att allt är synkat men att
något inte är friskt: titta på poddarna i appens namespace. Argo CD:s UI
visar samma sak per resurs.

### Larmet når inte Mattermost

1. Brinner det? Prometheus *Alerts*, eller larmkommandot i hälsokollen.
2. Kom det fram till Alertmanager, och är det tystat? Alertmanagers sida.
3. Fel när det skickas:
   `kubectl -n monitoring logs alertmanager-monitoring-kube-prometheus-alertmanager-0 -c alertmanager | grep -i error`
4. Finns webhooken? `kubectl -n monitoring get secret alertmanager-mattermost`
   (bara namnet, nyckeln heter `url`).
