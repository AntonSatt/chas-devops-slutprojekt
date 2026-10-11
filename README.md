# Grupp 1 - slutprojekt DevOps fördjupning

Kubernetes-kluster med 3 control planes i Hetzner Cloud och en dedikerad
worker, byggt från GitLab CI med Terraform och Ansible.

Deadline 2026-10-25, Final Lab 2026-10-26. Alla ska kunna förklara alla delar.

Ny i projektet, eller vill du förstå hur allt hänger ihop? Bygg ett eget
kluster från noll med [steg-för-steg-guiden](docs/steg-for-steg.md). Den
visar också vilka delar som är klara.

## Arbetssätt

- `main` är skyddad, allt går via merge request.
- Grenar: `feature/<del>`, `fix/<vad>`, `docs/<vad>`, t.ex. `feature/argocd`.
- Commits: `typ(område): vad commiten gör`, på svenska, t.ex.
  `feat(ansible): installera k3s på control planes`.
- Be någon annan titta på din MR innan merge. GitLab Free kan inte kräva
  det, så det är en överenskommelse. Pipelinen ska vara grön.
- Anteckningar per del i `docs/<del>/`: vad som fungerar, vad som inte gör
  det. Vi jobbar på olika tider.
- Discord för snack, Mattermost bara för larm, avstämning en gång i veckan.

## CI-variabler

Inga hemligheter i git. Allt ligger under *Settings > CI/CD > Variables*,
masked men inte protected, så att pipelines på grenar också kan testa.
Skyddet ligger i pipelinen i stället: på grenar körs bara validate och
`terraform plan`, apply, Ansible och destroy körs bara på `main`.

| Variabel | Innehåll |
|---|---|
| `HCLOUD_TOKEN` | Hetzner API-token (masked) |
| `TF_VAR_tsig_secret` | TSIG-secret för DNS (masked) |
| `GROUP1_SSH_KEY` | gruppens privata SSH-nyckel, typ File |
| `MATTERMOST_WEBHOOK_URL` | webhook för larm (masked) |
| `K3S_TOKEN` | klustrets join-token (masked) |
| `GRAFANA_ADMIN_PASSWORD` | Grafana-admin (masked) |
| `ARGOCD_REPO_USER` / `ARGOCD_REPO_TOKEN` | deploy-token så Argo CD kan läsa repot (token masked) |
| `SYNAPSE_POSTGRES_PASSWORD` / `SYNAPSE_REGISTRATION_SHARED_SECRET` | Synapse lösenord till Postgres och hemligheten för att skapa användare (masked) |

Skicka aldrig värden i klartext i en kanal.

## Terraform från din egen dator

Terraform-state ligger i GitLab (*Operate > Terraform states*), inte i en fil
på någons laptop. Var och en har en egen state och ett eget kluster, med sitt
namn som prefix på alla resurser. Den delade staten
`grupprojekt-terraform-state` är prod (`cluster_name = group1`) och ändras
bara via merge request.

Ska du bara köra Ansible behöver du inget av detta, se *Ansible* nedan.

Som Developer kan du inte skriva state i GitLab. Kör då lokal state, se
steg 3 i [steg-för-steg-guiden](docs/steg-for-steg.md).

### Det här behöver du

- En personal access token i GitLab med scope `api`: avataren > *Edit
  profile* > *Access tokens*. Den visas bara en gång.
- `HCLOUD_TOKEN`, som du hittar under *Settings > CI/CD > Variables*.
- Värden för variablerna i `terraform/variables.tf`:

| Variabel | Värde |
|---|---|
| `cluster_name` | ditt eget namn för dev-miljö, tex 'thomas'. Prod är 'group1' och sätts snart bara av CI :) |
| `admin_cidr` | din publika IP som `1.2.3.4/32`, den enda som når port 6443 på ditt kluster |
| `worker_count` | valfri, standard `0`. Sätt `1` för en worker-VM i ditt kluster, se *Workern* nedan. Sätts aldrig för prod |

`worker_ip` har ett standardvärde i koden och behöver inte sättas. Adressen
är publik och statisk, så den står i git precis som i
`ansible/inventory/worker.ini` och `dns/main.tf`. Ändras den måste alla tre
filerna ändras.

Lägg alltihop i en `.envrc` i repots rot (gitignorerad, laddas av direnv),
aldrig med `export` direkt i terminalen, eftersom det hamnar i
skalhistoriken:

```bash
export HCLOUD_TOKEN=...
export GITLAB_ACCESS_TOKEN=...
export GITLAB_USER_NAME=<ditt-gitlab-namn>
export TF_VAR_cluster_name=...
export TF_VAR_admin_cidr=...
```

Kör `direnv allow` efter varje ändring i filen. Ha bara den här enda
`.envrc`: direnv läser den närmaste filen, så en `.envrc` i `ansible/` eller
`terraform/` gör att den i roten inte läses alls.

### Init

Från `terraform/`. Byt `<ditt-namn>` mot samma namn som du har i
`cluster_name`, t.ex. `thomas-state`:

```bash
./setup.sh <ditt-namn>-state
```

Scriptet pekar Terraform mot din egen state i GitLab. Den syns under
*Operate > Terraform states* först efter din första `apply`. Kör scriptet
igen med ett annat namn för att byta state. Ingenting kopieras mellan dem.

Får du `address argument is required` har du kört `terraform init` direkt i
stället för scriptet.

Kör sedan `terraform plan`. På en ny state ska den bara visa `+` för
`<ditt-namn>-*`. Visar den `-` eller `~` på något som inte heter ditt namn
står du på fel state: kör inte `apply`.

### Regler

- **Din egen state är din.** `plan`, `apply` och `destroy` så mycket du vill,
  från vilken gren som helst. Det påverkar bara servrar med ditt namn.
- **Riv innan du slutar för dagen** med `terraform destroy`. Servrarna kostar
  per timme och spelreglerna kräver det.
- **Kör aldrig `setup.sh grupprojekt-terraform-state`.** Prod ändras via
  merge request, inte från någons dator. Ett `destroy` där river gruppens
  kluster.
- **Säger `plan` att state är låst** kör du redan Terraform i ett annat
  fönster. Använd `terraform force-unlock` bara om du vet att ingen körning
  pågår.

## Ansible

Kör allt från `ansible/`, annars läses inte `ansible.cfg`. Du behöver
`HCLOUD_TOKEN`, gruppens privata nyckel i `~/.ssh/group1_hetzner` och en
egen `K3S_TOKEN`.

Collections installeras till `ansible/collections/` (gitignorerad). Kör om
när `requirements.yml` har ändrats, annars hittar Ansible inte nya moduler:

```bash
ansible-galaxy collection install -r requirements.yml -p collections --force
```

`K3S_TOKEN` är join-token för ditt kluster. Alla control planes i ett kluster
måste ha samma, så den skapas en gång och sparas i `.envrc` i repots rot.
Från `ansible/`:

```bash
echo "export K3S_TOKEN=$(openssl rand -hex 32)" >> ../.envrc
direnv allow
```

Utan direnv: kör `source ../.envrc` i varje ny terminal. Skapa inte en ny token
med `export` direkt i terminalen, och byt aldrig token på ett kluster som
redan finns, då kan resten av noderna inte ansluta. Din token gäller bara
ditt kluster. Prod har en egen i CI-variabeln med samma namn. Saknas
variabeln stoppar playbooken innan något installeras.

Inventoryn frågar Hetzners API direkt och läser aldrig Terraform-state. Den
ser allas kluster, med en grupp per kluster: `cluster_<namn>`. Prod är
`cluster_group1`, där även bare metal-workern ingår. Gruppen `workers`
innehåller bare metal-workern och alla worker-VM:ar i dev.

**`site.yml` körs alltid mot ett kluster, som du väljer med `-e cluster`.**
Playen riktas mot `cluster_{{ cluster }}`. Glömmer du `-e` avbryter Ansible
med `'cluster' is undefined` innan något körs, i stället för att träffa alla
kluster, även prod och de andras. Kontrollera först vilka servrar som
träffas:

```bash
ansible-playbook site.yml -e cluster=<ditt-namn> --list-hosts
ansible-playbook site.yml -e cluster=<ditt-namn>
```

Ad hoc-kommandon (`ansible all ...`) har inget sådant skydd. Där gäller
`--limit cluster_<ditt-namn>`, annars träffas alla kluster. Observera att
`ansible-inventory --graph` inte bryr sig om `--limit`, så den duger inte
som kontroll.

### Workern

I prod har alla control planes `NoSchedule`-taint
(`group_vars/cluster_group1.yml`), så workern är den enda nod där appar
schemaläggs. Det kräver uppgiften. Klustrets egna komponenter, som CoreDNS
och Traefik, tål taint och kan ändå hamna på en control plane.

Dev har ingen taint och normalt ingen worker, så där kör control planes
apparna. Fungerar något i dev men blir `Pending` i prod, kör
`kubectl describe pod <namn>` och läs *Events*.

Workern ansluter som k3s-agent till klustrets första control plane. Rollen
`k3s_agent` sätter först upp ufw, sedan k3s. Öppna portar på workern:

| Port | Från | Varför |
|---|---|---|
| 22/tcp | alla | SSH, öppnas före allt annat så att ingen låses ute |
| 10250/tcp | klustrets control planes | kubelet: loggar, exec och metrics |
| 51820/udp | klustrets control planes | WireGuard, krypterad pod-trafik mellan noderna |
| alla | `10.42.0.0/16` | k3s poddnät, poddar som pratar med noden |
| alla | `10.43.0.0/16` | k3s service-nät |
| 80/tcp, 443/tcp | alla | ingress, wildcard-posten i DNS pekar hit |

Regler som redan fanns på prod-workern lämnas orörda, ufw-modulen lägger
bara till.

**Testa workern i ditt eget kluster** innan prod. Sätt `worker_count = 1`,
kör `terraform apply` och sedan:

```bash
ansible-playbook site.yml -e cluster=<ditt-namn> -e k3s_taint_control_planes=true
```

Med taint på alla control planes och en worker ser ditt kluster ut som prod.
Taint sätts bara vid installation, så klustret måste vara nybyggt.

## DNS

`dns/` skapar en enda post: `*.group-1.doe25.chas-lab.dev` pekar på
workern. k3s lastbalanserare (`svclb`) lyssnar på 80 och 443 på varje nod,
även workern, och skickar trafiken vidare till Traefik var den än körs. Varje
app under `group-1` nås därför utan att någon behöver lägga till en egen
post.

Posterna skrivs till `ns1.chas-lab.dev` med RFC 2136, signerade med gruppens
TSIG-nyckel. Nyckeln får bara skriva under `group-1`. `group-1` är ingen egen
zon, så posten ligger i zonen `doe25.chas-lab.dev`.

### En egen, delad state

`dns/` har en state som heter `dns`, skild från klustrens. Posten finns en
gång för hela gruppen och pekar på workern, som inte rivs. Låg den i
`terraform/` skulle varje persons state försöka äga samma post, och en
`destroy` på ditt kluster skulle ta bort den för alla.

Därför gäller samma regel som för prod: `dns` ändras via merge request.
Kör aldrig `terraform destroy` här.

### Köra lokalt

Utöver `GITLAB_ACCESS_TOKEN` och `GITLAB_USER_NAME` från avsnittet ovan
behövs TSIG-secreten i `.envrc`. Värdet finns i CI-variabeln med samma namn:

```bash
export TF_VAR_tsig_secret=...
```

Från `dns/`:

```bash
../terraform/setup.sh dns
terraform plan
```

Kontrollera att posten fungerar med valfritt namn under `group-1`:

```bash
dig +short test.group-1.doe25.chas-lab.dev
```

Ska ge workerns IP, `203.0.113.10`.

## GitOps (Argo CD)

Efter k3s installerar `site.yml` Argo CD och en root-app. Sen kommer allt i
klustret från git: en ny app är en ny fil i `kubernetes/apps/templates/`.
Hur det hänger ihop, och övningar: [docs/gitops/argo-cd.md](docs/gitops/argo-cd.md).

Argo CD måste kunna läsa repot. Lägg till i `.envrc`, värdena finns i
CI-variablerna med samma namn. Som Developer ser du inte dem, skapa då en
egen token med bara `read_repository`:

```bash
export ARGOCD_REPO_USER=...
export ARGOCD_REPO_TOKEN=...
```

Ditt dev-kluster följer `main`. Ska det följa din gren, pusha grenen och
kör playbooken med den:

```bash
MIN_GREN=feature/monitoring
ansible-playbook site.yml -e cluster=$TF_VAR_cluster_name -e argocd_revision=$MIN_GREN
```

Status och UI, från repots rot. Port-forward går via port 6443, så det
fungerar bara från din `admin_cidr`:

```bash
export KUBECONFIG=$PWD/$TF_VAR_cluster_name.kubeconfig
kubectl -n argocd get applications
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
kubectl -n argocd port-forward svc/argocd-server 8080:80
```

Öppna http://localhost:8080 och logga in som `admin`.

## Monitoring

Appen `monitoring` är kube-prometheus-stack: Prometheus, Grafana,
Alertmanager, node-exporter och kube-state-metrics. Den plockar upp
ServiceMonitors, dashboards och larmregler från alla namespaces. Hur det
hänger ihop, och övningar: [docs/monitoring/monitoring.md](docs/monitoring/monitoring.md).

Grafanas admin-lösenord kommer från CI-variabeln `GRAFANA_ADMIN_PASSWORD`.
I dev skapar du ett eget, en gång, från repots rot:

```bash
echo "export GRAFANA_ADMIN_PASSWORD=$(openssl rand -hex 16)" >> .envrc
```

Prometheus och Grafana, med `KUBECONFIG` satt som ovan:

```bash
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090
kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80
```

Prometheus på http://localhost:9090, Grafana på http://localhost:3000 som
`admin`.

## Larm

Larmregler är PrometheusRules. Alertmanager skickar larm med `warning` eller
`critical` till Mattermost och ett OK när de clearas. Rubriken säger vilket
kluster larmet kommer från. Hur kedjan fungerar, och övningar:
[docs/monitoring/larm.md](docs/monitoring/larm.md).

Webhooken kommer från CI-variabeln `MATTERMOST_WEBHOOK_URL`, lägg den i
`.envrc`. Dev-kluster larmar i samma kanal som prod, men rubriken visar
vilket kluster det gäller.

Testa kedjan med appen `larmtest`: sätt `replicas: 1` i
`kubernetes/manifests/larmtest/deployment.yaml`, pusha och vänta på LARM i
Mattermost. Tillbaka till `0` ger OK. Alertmanager når du så här:

```bash
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-alertmanager 9093:9093
```

## Synapse

Matrix Synapse med Element web, en egen chart i `charts/synapse/`. Argo CD
deployar den som appen `synapse`. Valen, övningar och hur man testar lokalt:
[charts/synapse/README.md](charts/synapse/README.md).

Secreten kommer från CI-variablerna `SYNAPSE_POSTGRES_PASSWORD` och
`SYNAPSE_REGISTRATION_SHARED_SECRET`. I dev skapar du egna, en gång, från
repots rot:

```bash
echo "export SYNAPSE_POSTGRES_PASSWORD=$(openssl rand -hex 16)" >> .envrc
echo "export SYNAPSE_REGISTRATION_SHARED_SECRET=$(openssl rand -hex 32)" >> .envrc
```

Första användaren skapas med `register_new_matrix_user`, se
`charts/synapse/templates/NOTES.txt`.

## Spelregler

Från `group-project.pdf`, avsnitt 6. Kontrolleras automatiskt och löpande.

- SSH-användaren `group1` + gruppnyckeln + port 22 ska fungera på alla
  maskiner vi skapar.
- VM-typer: `cx23`, `cax11`, `cpx12`, inga andra.
- Under 40 EUR/månad. En avstängd server kostar fullt, så radera i stället.
- Inget farligt exponerat (databaser, container-sockets, gränssnitt utan
  inloggning). Varje öppen port ska gå att motivera.
- Egna labb-VM:ar rivs när du är klar.
