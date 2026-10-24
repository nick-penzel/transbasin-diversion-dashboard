# Diversions and transfers between basins

## Records and telemetry

Colorado DWR publishes two kinds of diversion data:

- **Telemetry**: provisional daily flow from gauges at the headgate, available within hours.
- **Approved records**: the official daily and monthly amounts, reviewed by water commissioners, usually about a year behind.

The dashboard uses approved records where they exist and fills recent months with telemetry, flagged provisional. Where both exist they agree within about 1% for the transmountain tunnels.

## Water classes

Monthly records split each structure's diversion into water classes with a source, use, and type code (DWR Diversion Records Standard). The headgate total is the administrative class `S:X U:Q T:0`, with the largest class as a fallback. Use breakdowns drop administrative, release, and quantity-only classes and records carried from another structure, so water is not counted twice. Tunnels that only convey water record "quantity only", so their use is recorded at the receiving structure.

## Transfers between basins

Each transbasin structure has a source and destination basin. Gunnison basin structures count toward the Colorado basin and Yampa structures toward the Yampa/White, matching the eight basin polygons; transfers within one basin are dropped. CDSS has records for about 30 structures before 2013 and about 45 after, so totals before 2013 undercount and public pages start in 2013.

## Water rights

Decreed rights come from the CDSS net amount rights table at both the accounting structure and the point of diversion. Rights are in cfs or acre-feet; a lower administration number is more senior.
