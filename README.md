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
som **protected** (bara `main` får dem, feature-grenar kan inte ändra
infrastrukturen).

| Variabel | Innehåll |
|---|---|
| `HCLOUD_TOKEN` | Hetzner API-token (masked) |
| `TF_VAR_tsig_secret` | TSIG-secret för DNS (masked) |
| `TF_VAR_ssh_public_key` | gruppens publika SSH-nyckel |
| `GROUP1_SSH_KEY` | gruppens privata SSH-nyckel, typ File |
| `MATTERMOST_WEBHOOK_URL` | webhook för larm (masked) |
| `K3S_TOKEN` | klustrets join-token (masked) |
| `GRAFANA_ADMIN_PASSWORD` | Grafana-admin (masked) |
| `ARGOCD_REPO_USER` / `ARGOCD_REPO_TOKEN` | deploy-token så Argo CD kan läsa repot (token masked) |

Skicka aldrig värden i klartext i en kanal.

## Spelregler

- `group1` + gruppnyckeln + port 22 ska fungera på alla maskiner, annars
  raderar läraren dem.
- VM-typer i ordningen `cx23`, `cax11`, `cpx12`. Egna labb-VM:ar rivs när
  du är klar.
