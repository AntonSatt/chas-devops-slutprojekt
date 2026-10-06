# Grupp 1 - slutprojekt DevOps fördjupning

Kubernetes-kluster med 3 control planes i Hetzner Cloud och en dedikerad
worker, byggt från GitLab CI med Terraform och Ansible.

Deadline 2026-10-25, Final Lab 2026-10-26. Alla ska kunna förklara alla delar.

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

Skicka aldrig värden i klartext i en kanal.

## Terraform från din egen dator

Terraform-state ligger i GitLab (*Operate > Terraform states*), inte i en fil
på någons laptop. Var och en har en egen state och ett eget kluster, med sitt
namn som prefix på alla resurser. Den delade staten
`grupprojekt-terraform-state` är prod (`cluster_name = group1`) och ändras
bara via merge request.

Ska du bara köra Ansible behöver du inget av detta, se *Ansible* nedan.

### Det här behöver du

- En personal access token i GitLab med scope `api`: avataren > *Edit
  profile* > *Access tokens*. Den visas bara en gång.
- `HCLOUD_TOKEN`, som du hittar under *Settings > CI/CD > Variables*.
- Värden för variablerna i `terraform/variables.tf`:

| Variabel | Värde |
|---|---|
| `cluster_name` | ditt eget namn för dev-miljö, tex 'thomas'. Prod är 'group1' och sätts snart bara av CI :) |
| `admin_cidr` | din publika IP som `1.2.3.4/32`, den enda som når port 6443 på ditt kluster |

`worker_ip` har ett standardvärde i koden och behöver inte sättas. Adressen
är publik och statisk, så den står i git precis som i
`ansible/inventory/worker.ini`. Ändras den måste båda filerna ändras.

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

Kör `direnv allow` efter varje ändring i filen.

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
`HCLOUD_TOKEN` och gruppens privata nyckel i `~/.ssh/group1_hetzner`.

Inventoryn frågar Hetzners API direkt och läser aldrig Terraform-state. Den
ser allas kluster, med en grupp per kluster: `cluster_<namn>`. Prod är
`cluster_group1`, där även bare metal-workern ingår.

**Rikta alltid mot ett kluster med `--limit`.** Utan den träffar körningen
alla kluster, även prod och de andras. Kontrollera först vilka servrar som
träffas:

```bash
ansible all --limit cluster_<ditt-namn> --list-hosts
ansible-playbook <playbook> --limit cluster_<ditt-namn>
```

`ansible-inventory --graph` visar alla grupper men bryr sig inte om
`--limit`, så den duger inte som kontroll.

## Spelregler

Från `group-project.pdf`, avsnitt 6. Kontrolleras automatiskt och löpande.

- SSH-användaren `group1` + gruppnyckeln + port 22 ska fungera på alla
  maskiner vi skapar.
- VM-typer: `cx23`, `cax11`, `cpx12`, inga andra.
- Under 40 EUR/månad. En avstängd server kostar fullt, så radera i stället.
- Inget farligt exponerat (databaser, container-sockets, gränssnitt utan
  inloggning). Varje öppen port ska gå att motivera.
- Egna labb-VM:ar rivs när du är klar.
