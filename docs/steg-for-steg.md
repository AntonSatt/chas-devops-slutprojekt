# Steg för steg: bygg hela klustret själv

Den här guiden bygger ett eget kluster från noll, i samma ordning som
pipelinen ska göra det i prod. Målet är att förstå vad vi har byggt: varje
steg säger vad som händer, var koden ligger och hur du ser att det
fungerade. Då kan du ändra i vilken del som helst och veta vad det påverkar.

Gå igenom guiden från början till slut minst en gång. På labben lottas
delarna och ändringar görs via commit, så alla behöver ha sett hela kedjan.

Varför sakerna är byggda som de är står i README och i `docs/`. Guiden
länkar dit i stället för att upprepa det.

## Läget per 2026-10-11

*Klart* betyder byggt och testat i ett dev-kluster. Inget är byggt i prod
än, det väntar på pipelinen. Uppdatera tabellen i samma MR som en del blir
klar.

| Del | Läge | Var i repot | Steg |
|---|---|---|---|
| Kluster: control planes och en worker | klart | `terraform/`, `ansible/` | 3, 4 |
| Krypterad trafik mellan noderna | klart, WireGuard i k3s | `ansible/roles/k3s_server/` | 4 |
| DNS: wildcard mot workern | klart | `dns/` | gemensam, rörs inte här |
| Certifikat och HTTPS | saknas | | |
| Continuous deployment | klart, Argo CD | `kubernetes/apps/` | 4, 7 |
| Monitoring | klart | `kubernetes/values/monitoring.yaml` | 6 |
| Larm | klart | `kubernetes/values/monitoring.yaml`, `kubernetes/manifests/larmtest/` | 7 |
| Loggar | saknas | | |
| Secrets | delvis: CI-variabler som Ansible gör till Secrets, Sealed Secrets planerat | `ansible/roles/app_secrets/` | 2, 4 |
| Pipeline | saknas, ingen `.gitlab-ci.yml` | | |
| Synapse, individuell del | klart | `charts/synapse/` | 6 |

## Översikt

```mermaid
flowchart LR
  E[".envrc"] --> T["Terraform: servrar och brandvägg"]
  T --> A["Ansible: k3s, secrets, Argo CD"]
  A --> R["Argo CD: allt annat från git"]
  R --> X["monitoring, larm, synapse"]
```

| Steg | Verktyg | Vad som händer | I prod, när pipelinen finns |
|---|---|---|---|
| 0-2 | du | verktyg, hemligheter och `.envrc` | CI-variablerna |
| 3 | Terraform | VM:ar och brandvägg med ditt namn | samma kod, `cluster_name = group1` |
| 4 | Ansible | användare, k3s, secrets och Argo CD | samma playbook, `-e cluster=group1` |
| 5-6 | kubectl | kolla att allt kom upp | samma |
| 7 | git | ändra klustret med en commit | samma, via MR till `main` |
| 8 | Terraform | riv | prod rivs bara vid genrepet |

Varje kodblock börjar i repots rot.

## Steg 0: verktyg

| Verktyg | Används i |
|---|---|
| `terraform` eller `tofu` | steg 3 och 8 |
| `ansible`, ansible-core räcker | steg 4 |
| `kubectl` | steg 5 till 7 |
| `direnv` | laddar `.envrc`, valfritt |
| `git`, `openssl`, `curl`, `jq` | små saker längs vägen |

Inventoryn i Ansible (collectionen `hetzner.hcloud`) behöver Python-paketen
`requests` och `python-dateutil` i samma Python som Ansible. Installerade du
Ansible med pipx:

```bash
pipx inject ansible-core requests python-dateutil
```

Står paketet som `ansible` i `pipx list`, byt `ansible-core` mot `ansible`.
Annars: `pip install requests python-dateutil` i samma miljö som Ansible.

Kontrollera:

```bash
terraform version
ansible --version
kubectl version --client
```

Klona repot om du inte redan har det:

```bash
git clone https://git.chas-lab.dev/devops-grupp-1/grupprojekt.git
cd grupprojekt
```

## Steg 1: hemligheterna

Inga hemligheter i git och inga i klartext i en kanal. Behöver någon ett
värde skickas det med en engångslänk.

| Det du behöver | Maintainer | Developer |
|---|---|---|
| `HCLOUD_TOKEN` | CI-variabeln, *Settings > CI/CD > Variables* | engångslänk från en Maintainer |
| gruppens privata SSH-nyckel | CI-variabeln `GROUP1_SSH_KEY` | engångslänk |
| `MATTERMOST_WEBHOOK_URL` | CI-variabeln | engångslänk |
| `ARGOCD_REPO_USER` och `ARGOCD_REPO_TOKEN` | CI-variablerna | egen personal access token med bara `read_repository`, ditt GitLab-namn som user |
| `GITLAB_ACCESS_TOKEN` | egen personal access token med scope `api` | behövs inte, du kör lokal state i steg 3 |

Personal access token skapar du under avataren > *Edit profile* > *Access
tokens*. Den visas bara en gång. Resten av värdena skapar du själv i steg 2.

Developer kan varken se CI-variablerna eller skriva Terraform-state i
GitLab. Därför ser steg 3 lite annorlunda ut för dig.

### SSH-nyckeln

Spara nyckeln som `~/.ssh/group1_hetzner`, där letar `ansible/ansible.cfg`.
Klistra in den i din editor, inte med `echo`, så hamnar den inte i
skalhistoriken. Filen måste sluta med en radbrytning, annars säger ssh
`invalid format`.

```bash
chmod 600 ~/.ssh/group1_hetzner
ssh-keygen -y -f ~/.ssh/group1_hetzner
```

Den andra raden räknar fram den publika nyckeln. Den ska sluta på
`group1-hetzner-lab` och vara samma som `group1_ssh_public_key` i
`ansible/group_vars/all.yml`. Ansible lägger in just den på användaren
`group1` på varje maskin, så att läraren alltid kommer in.

## Steg 2: `.envrc`

Alla värden ligger i en enda fil: `.envrc` i repots rot. Den är
gitignorerad och laddas av direnv när du går in i repot, även i `ansible/`
och `terraform/`. Lägg den aldrig i en undermapp. direnv läser bara den
närmaste filen, så en `.envrc` i `ansible/` gör att den i roten inte läses
alls.

Skapa filen i din editor med det här innehållet och fyll i värdena från
steg 1:

```bash
# Hetzner och GitLab
export HCLOUD_TOKEN=...
export GITLAB_ACCESS_TOKEN=...
export GITLAB_USER_NAME=...

# Ditt kluster
export TF_VAR_cluster_name=...
export TF_VAR_admin_cidr=...
export TF_VAR_control_plane_count=1
export TF_VAR_worker_count=1

# Apparna
export ARGOCD_REPO_USER=...
export ARGOCD_REPO_TOKEN=...
export MATTERMOST_WEBHOOK_URL=...
```

| Variabel | Värde |
|---|---|
| `GITLAB_USER_NAME` | ditt användarnamn i GitLab. Developer hoppar över den och `GITLAB_ACCESS_TOKEN` |
| `TF_VAR_cluster_name` | ditt förnamn med små bokstäver. Prefix på allt du skapar. Aldrig `group1`, det är prod |
| `TF_VAR_admin_cidr` | din publika IP plus `/32`. `curl -s https://ifconfig.me` visar den. Den enda adress som når port 6443 på ditt kluster |
| `TF_VAR_control_plane_count` | `1` räcker i dev och är billigare. Prod har 3 |
| `TF_VAR_worker_count` | `1` ger en worker-VM, så att ditt kluster ser ut som prod |

Byter du nätverk, till exempel mellan skolan och hemma, ändra `admin_cidr`
och kör `terraform apply` igen. Annars når du inte ditt kluster med
`kubectl`.

Sedan värdena du skapar själv. Kör raderna **en gång**, från repots rot:

```bash
echo "export K3S_TOKEN=$(openssl rand -hex 32)" >> .envrc
echo "export GRAFANA_ADMIN_PASSWORD=$(openssl rand -hex 16)" >> .envrc
echo "export SYNAPSE_POSTGRES_PASSWORD=$(openssl rand -hex 16)" >> .envrc
echo "export SYNAPSE_REGISTRATION_SHARED_SECRET=$(openssl rand -hex 32)" >> .envrc
chmod 600 .envrc
direnv allow
```

Kör du raderna igen hamnar nya värden sist i filen, och de vinner. En ny
`K3S_TOKEN` på ett kluster som redan finns gör att noderna inte kan
ansluta. Ditt kluster har sina egna värden, prods ligger i CI-variablerna.

Utan direnv: kör `source .envrc` från repots rot i varje ny terminal.
Skriv aldrig `export` med ett hemligt värde direkt i terminalen, det hamnar
i skalhistoriken.

Kontrollera att allt är satt, utan att skriva ut värdena:

```bash
for v in HCLOUD_TOKEN GITLAB_ACCESS_TOKEN GITLAB_USER_NAME \
  TF_VAR_cluster_name TF_VAR_admin_cidr K3S_TOKEN \
  ARGOCD_REPO_USER ARGOCD_REPO_TOKEN MATTERMOST_WEBHOOK_URL \
  GRAFANA_ADMIN_PASSWORD SYNAPSE_POSTGRES_PASSWORD SYNAPSE_REGISTRATION_SHARED_SECRET; do
  if printenv "$v" > /dev/null; then echo "ok      $v"; else echo "SAKNAS  $v"; fi
done
```

Gå in i `ansible/` och kör loopen igen. Svaret ska bli detsamma. Som
Developer blir de två `GITLAB_`-raderna `SAKNAS`, det är väntat.
