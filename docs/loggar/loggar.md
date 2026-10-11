# Loggar

Loki och Alloy samlar loggar från alla noder och alla workloads på ett ställe.

## Loki

Loki tar emot loggar från Alloy, lagrar dem och sorterar dem så att de är lätta att hitta senare. Utan Loki försvinner loggarna när en pod startas om. Med Loki finns de kvar.

## Varför monolithic och disk

Vi kör Loki i monolithic-läge, alltså en enda pod, och sparar loggarna på disk. Loggvolymen är liten, så flera poddar och objektlagring (till exempel MinIO) vore slöseri med resurser. Det är också ett system mindre att sätta upp och förstå.

## Varför auth_enabled: false

Loki kan kräva att varje anrop talar om vilken tenant (vem) det gäller. Vi är en enda grupp med ett kluster, så det behövs inte.