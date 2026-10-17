# Loggar

Loki och Alloy samlar loggar från alla noder och alla workloads på ett ställe.

## Loki

Loki tar emot loggar från Alloy, lagrar dem och sorterar dem så att de är lätta att hitta senare. Utan Loki försvinner loggarna när en pod startas om. Med Loki finns de kvar.

## Varför monolithic och disk

Vi kör Loki i monolithic-läge, alltså en enda pod, och sparar loggarna på disk. Loggvolymen är liten, så flera poddar och objektlagring (till exempel MinIO) vore slöseri med resurser. Det är också ett system mindre att sätta upp och förstå.

## Varför auth_enabled: false

Loki kan kräva att varje anrop talar om vilken tenant (vem) det gäller. Vi är en enda grupp med ett kluster, så det behövs inte.



## Alloy

Alloy hämtar loggar från poddarna och skickar dem till Loki.

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