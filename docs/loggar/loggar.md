# Loggar

Loki och Alloy samlar loggar från alla noder och alla workloads på ett ställe.

## Loki

Loki tar emot loggar från Alloy, lagrar dem och sorterar dem så att de är lätta att hitta senare. Utan Loki försvinner loggarna när en pod startas om. Med Loki finns de kvar.

## Varför monolithic och disk

Vi kör Loki i monolithic-läge, alltså en enda pod, och sparar loggarna på disk. Loggvolymen är liten, så flera poddar och objektlagring (till exempel MinIO) vore slöseri med resurser. Det är också ett system mindre att sätta upp och förstå.

## Varför auth_enabled: false

Loki kan kräva att varje anrop talar om vilken tenant (vem) det gäller. Vi är en enda grupp med ett kluster, så det behövs inte.



## Alloy

Alloy hämtar loggar från poddarna och från journald på noderna, och skickar dem till Loki.

### Varför DaemonSet

Alloy körs som en DaemonSet, alltså exakt en pod per nod. Loggarna ligger lokalt på varje nod, så varje nod behöver en egen Alloy som samlar in dem. Kommer det en ny nod får den automatiskt en Alloy-pod.

### Konfigurationen

Konfigurationen ligger i `kubernetes/values/alloy.yaml` och kommer från Alloys dokumentation, "Collect Kubernetes logs and forward them to Loki".

- `discovery.kubernetes` hittar poddarna på noden
- `discovery.relabel` sätter etiketter som namespace, pod och container
- `loki.source.kubernetes` läser poddarnas loggar
- `loki.write` skickar loggarna till Loki

### Så kontrollerar man att det fungerar

Öppna en tunnel till Loki och fråga vilka etiketter den har fått loggar med:

    kubectl port-forward -n logging svc/loki 3100:3100 &
    curl -s http://127.0.0.1:3100/loki/api/v1/labels

Finns `namespace`, `pod` och `container` i svaret har Alloy skickat loggar till Loki.



## journald

journald är Linux egen systemlogg på noden. Poddloggarna visar bara apparnas loggar. Med journald får vi också det som händer i systemet, till exempel k3s, SSH och kärnan, och därmed en helhetsbild.

### Konfigurationen

- `loki.source.journal "read"` läser journald och skickar till Loki.
- `loki.relabel "journal"` döper om fält. Alla journald-fält börjar med `__` (till exempel `__journal__systemd_unit`), och sådana fält slängs innan loggen skickas. Vi döper om dem till `unit` och `node` så att de blir kvar som etiketter.
- `varlog: true` behövs eftersom journalfilerna ligger på nodens disk. Alloy körs i en container med eget filsystem som inte ser nodens filer. `varlog` monterar nodens `/var/log` in i containern.

### Problem vi löste: tom machine-id

journald sparar filerna i en undermapp som heter som nodens machine-id, `/var/log/journal/<machine-id>/`. Containerns `/etc/machine-id` var tom, så Alloy visste inte vilken undermapp den skulle läsa, och samlade ingenting, utan att ge fel. Lösningen var att montera nodens `/etc/machine-id` in i containern (`alloy.mounts.extra` och `controller.volumes.extra`).

### Så kontrollerar man att det fungerar

Med port-forward igång frågar man Loki vilka värden etiketten `job` har:

    curl -s http://127.0.0.1:3100/loki/api/v1/label/job/values

Finns `journal` i svaret har Loki tagit emot journald-loggar.



## Toleration

En taint är som en skylt på en nod. Den stoppar nya poddar från att placeras där. En pod som ändå ska köras på noden behöver en toleration som matchar tainten.

Prod-klustrets control planes har tainten `node-role.kubernetes.io/control-plane:NoSchedule`. Den sätts av Ansible i `ansible/roles/k3s_server/tasks/main.yml`, men bara när `k3s_taint_control_planes` är sann. Därför har prod tainten men inte dev-klustren.

Utan toleration hamnar Alloy bara på workern, inte på de tre control planes. Då saknas loggarna därifrån. Därför har Alloy en toleration för tainten (`controller.tolerations` i `kubernetes/values/alloy.yaml`).

### Så testade vi det

1. Satte samma taint på dev-noden: `kubectl taint nodes adam-node-cp-0 node-role.kubernetes.io/control-plane:NoSchedule`
2. Tog bort Alloy-podden. `kubectl get daemonset -n logging` visade `DESIRED 0`: utan toleration ville Kubernetes inte placera någon Alloy på noden.
3. Uppdaterade Alloy med tolerationen. Då visade den `DESIRED 1` och `READY 1`.


## Grafana-datasource

Grafana hittar Loki genom en ConfigMap med labeln `grafana_datasource: "1"`. Grafana letar bara efter sådana ConfigMaps i sitt eget namespace, `monitoring`, så det är där den ligger. Det står i monitoring-chartets standardinställningar, och `monitoring.yaml` ändrar inte på det.

Filen ligger i `kubernetes/manifests/loggar/grafana-datasource.yaml` och pekar på `http://loki.logging.svc.cluster.local:3100`, adressen från Lokis NOTES.

## Argo CD

Loggdelen installeras av tre Argo CD-appar i `kubernetes/apps/templates/`:

- `loki` installerar Loki med `kubernetes/values/loki.yaml`
- `alloy` installerar Alloy med `kubernetes/values/alloy.yaml`
- `loggar` lägger in manifesten i `kubernetes/manifests/loggar/`, just nu Grafana-datasourcen

`loki` och `alloy` är byggda som `monitoring.yaml`, med charten från ett externt repo och values från vårt. `loggar` är byggd som `larmtest.yaml` och läser en mapp i repot. Chartversionerna är låsta, 18.15.1 för Loki och 1.13.1 för Alloy.


## Retention

Loki sparar loggar i 7 dagar (`retention_period: 168h`). Utan en gräns sparas
loggarna för alltid, disken blir full och Loki slutar ta emot loggar, utan larm.

Det är compactorn som rensar (`compactor.retention_enabled: true`). När retention
är på kräver Loki också `delete_request_store`, här `filesystem` eftersom loggarna
ligger på disk. Källa: Lokis dokumentation, "Log retention".

7 dagar räcker för felsökning och ryms på 5Gi. Diskens användning syns med:

    kubectl -n logging exec loki-0 -c loki -- df -h /var/loki