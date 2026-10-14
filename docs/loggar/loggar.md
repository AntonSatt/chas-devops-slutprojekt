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