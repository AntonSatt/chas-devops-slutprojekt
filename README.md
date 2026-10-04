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
på någons laptop. Alla som kör Terraform läser och skriver samma state, och
ser därmed samma servrar. Tills pipelinen kör `apply` gör vi det lokalt.

Ska du bara köra Ansible behöver du inget av detta. Inventoryn frågar
Hetzners API direkt och läser aldrig Terraform-state.

### Det här behöver du

- En personal access token i GitLab med scope `api`: avataren > *Edit
  profile* > *Access tokens*. Den visas bara en gång.
- `HCLOUD_TOKEN`, som du hittar under *Settings > CI/CD > Variables*.
- Värden för variablerna i `terraform/variables.tf`:

| Variabel | Värde |
|---|---|
| `cluster_name` | ditt eget namn för dev-miljö, tex 'thomas'. Prod är 'group1' och sätts snart bara av CI :) |
| `admin_cidr` | se varning nedan |

`worker_ip` har ett standardvärde i koden och behöver inte sättas. Adressen
är publik och statisk, så den står i git precis som i
`ansible/inventory/worker.ini`. Ändras den måste båda filerna ändras.

Lägg alltihop i en `.envrc` i repots rot (gitignorerad, laddas av direnv),
aldrig med `export` direkt i terminalen, eftersom det hamnar i
skalhistoriken:

```bash
export HCLOUD_TOKEN=...
export GITLAB_ACCESS_TOKEN=...
export TF_STATE_NAME=grupprojekt-terraform-state
export TF_VAR_cluster_name=...
export TF_VAR_admin_cidr=...
```

Kör `direnv allow` efter varje ändring i filen.

### Init

En gång per klon, från `terraform/`. Byt `<ditt-gitlab-namn>` mot ditt
användarnamn:

```bash
terraform init \
    -backend-config="address=https://git.chas-lab.dev/api/v4/projects/582/terraform/state/$TF_STATE_NAME" \
    -backend-config="lock_address=https://git.chas-lab.dev/api/v4/projects/582/terraform/state/$TF_STATE_NAME/lock" \
    -backend-config="unlock_address=https://git.chas-lab.dev/api/v4/projects/582/terraform/state/$TF_STATE_NAME/lock" \
    -backend-config="username=<ditt-gitlab-namn>" \
    -backend-config="password=$GITLAB_ACCESS_TOKEN" \
    -backend-config="lock_method=POST" \
    -backend-config="unlock_method=DELETE" \
    -backend-config="retry_wait_min=5"
```

Får du `address argument is required` har du kört `terraform init` utan
flaggorna. Kör sedan `terraform plan`. Står det `No changes` är du på samma
servrar som alla andra.

### Regler

- **`plan` får alla köra.** Den ändrar ingenting.
- **`apply` bara från `main`, och säg till i Discord först.** State vet
  inget om grenar: kör du `apply` från din gren blir din gren verklighet för
  hela gruppen, även om den aldrig mergas.
- **Aldrig `destroy`** utan att gruppen bestämt det. Det river allas maskiner.
- **`admin_cidr` styr vem som når port 6443.** Sätter du din egen IP och kör
  `apply` byter brandväggen till din adress, och alla andra blir utelåsta
  från Kubernetes API. Visar `plan` en ändring på `hcloud_firewall.cp` som du
  inte avsåg: kör inte `apply`.
- **Säger `plan` att state är låst** kör någon annan just nu. Vänta. Använd
  `terraform force-unlock` bara om du vet att ingen körning pågår.

## Spelregler

Från `group-project.pdf`, avsnitt 6. Kontrolleras automatiskt och löpande.

- SSH-användaren `group1` + gruppnyckeln + port 22 ska fungera på alla
  maskiner vi skapar.
- VM-typer: `cx23`, `cax11`, `cpx12`, inga andra.
- Under 40 EUR/månad. En avstängd server kostar fullt, så radera i stället.
- Inget farligt exponerat (databaser, container-sockets, gränssnitt utan
  inloggning). Varje öppen port ska gå att motivera.
- Egna labb-VM:ar rivs när du är klar.
