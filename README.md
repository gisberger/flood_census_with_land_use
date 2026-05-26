# Flood Exposure Analysis with Land Use Refinement in Landkreis Altötting, Bavaria

## What This Project Is About

This is the second iteration of my flood exposure analysis for Landkreis Altötting. The [first version](https://github.com/gisberger/flood-exposure-altoetting-v1) estimated affected population using a 100mx100m census grid overlaid with flood hazard polygons and a simple area-weighting approach.

This version refines the method by incorporating ALKIS land use data (residential building footprints) to distribute population more realistically. Instead of assuming people are spread uniformly across a census cell, the calculation now concentrates them in areas classified as residential, then checks how much of that residential area is flooded.

During the process, I also discovered that the BfG operates multiple flood risk map portals with different data vintages, which resolved a confusing discrepancy from the first project.

All SQL code was hand-written, with troubleshooting support by Claude model Opus 4.7.

---

## Key Improvement Over Version 1

**Version 1 formula:**
```
pop × (flooded area of cell / total cell area)
```

**Version 2 formula:**
```
pop × (flooded residential area in cell / total residential area in cell)
```

The difference: if a census cell is 80% farmland and 20% residential, and the flood zone covers the residential part, Version 1 assigns only 20% of the population (because 20% of the cell is flooded). Version 2 correctly assigns ~100% (because all the residential area is flooded). Conversely, if only farmland floods, Version 2 assigns 0 — nobody lives there.

This required precomputing the total residential area per census cell as a permanent table to avoid recalculating it for every query:

```sql
CREATE TABLE zensus_wohn_gesamt AS
SELECT z.id, SUM(ST_Area(ST_Intersection(z.geom, w.geom))) AS wohn_area
FROM zensus2022_100m z
JOIN wohnflaechen w ON ST_Intersects(z.geom, w.geom)
GROUP BY z.id;
```

Similarly, the intersection of flood zones with residential areas was precomputed per scenario:

```sql
CREATE TABLE wohnflaechen_hw_100 AS
SELECT ST_Intersection(h.geom, n.geom) AS geom
FROM hwgfhq100_15_04_2026 h 
JOIN nutzung_aoe n ON ST_Intersects(n.geom, h.geom)
JOIN adm_adm_2 a ON ST_Intersects(h.geom, a.geom)
WHERE a.name_2 LIKE '%Altötting%'
AND (n.bez LIKE '%Gebäude- und Freifläche Mischnutzung mit Wohnen§' 
     OR n.nutzart LIKE '%Wohnbaufläche%');
```

The final query per scenario then only needs one spatial intersection at runtime:

```sql
SELECT a.name_3 AS gemeinde,
       ROUND(SUM(z."Einwohner" * (ST_Area(ST_Intersection(z.geom, f.geom)) / w.wohn_area))::numeric, 0) AS betroffene
FROM zensus2022_100m z
JOIN wohnflaechen_hw_100 f ON ST_Intersects(z.geom, f.geom)
JOIN zensus_wohn_gesamt w ON z.id = w.id
JOIN adm_adm_3 a ON ST_Intersects(z.geom, a.geom)
WHERE a.name_2 LIKE '%Altötting%'
AND NOT (w.wohn_area = 0)
GROUP BY a.name_3;
```

---

## The BfG Data Confusion

During the first project, I compared my results against a BfG flood risk map that showed zero affected residents for several municipalities (Altötting, Tüßling, Teising, and others). This seemed wrong - my analysis clearly showed residential areas within flood zones there.

It turned out that the BfG operates two separate map portals:

- **HWRM 2019** (`geoportal.bafg.de/karten/HWRM/`) — The 2nd reporting cycle, ArcGIS-based layout. This version has complete data for Landkreis Altötting, and its values are much closer to my results.
- **HWRM current** (`geoportal.bafg.de/karten/HWRM_2026/`) — The 3rd reporting cycle, newer layout. This version shows zeros for many municipalities, likely because Bavaria's data upload for the 3rd cycle is still incomplete (the reporting deadline for updated hazard maps was December 2025, with management plans due December 2027).

Additionally, the LfU Bayern publishes separate Beiblätter (PDF supplements) per municipality with yet another set of numbers.

This version compares against the old and the current public maps to give a more complete picture.

---

## Final Comparison Table

| Municipality | Own (frequent) | BfG 2019 (frequent) | BfG current (frequent) | Own (HQ100) | BfG 2019 (HQ100) | BfG current (HQ100) | Own (extreme) | BfG 2019 (extreme) | BfG current (extreme) |
|---|---|---|---|---|---|---|---|---|---|
| Altötting | 0 | 0 | 0 | 996 | 910 | 0 | 4567 | 2490 | 0 |
| Burghausen | 2 | 0 | 1 | 41 | 0 | 30 | 441 | 190 | 190 |
| Burgkirchen a.d. Alz | 8 | 0 | 10 | 31 | 730 | 80 | 1423 | 0 | 1610 |
| Emmerting | 0 | 0 | 1 | 0 | 0 | 1 | 2835 | 2200 | 2660 |
| Garching a.d. Alz | 0 | 0 | 1 | 145 | 190 | 80 | 837 | 600 | 730 |
| Haiming | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| Kirchweidach | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| Marktl | 0 | 0 | 1 | 3 | 0 | 10 | 14 | 0 | 20 |
| Neuötting | 0 | 0 | 20 | 1058 | 450 | 40 | 2850 | 1560 | 1710 |
| Pleiskirchen | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| Reischach | 10 | 0 | 1 | 925 | 10 | 10 | 1726 | 30 | 30 |
| Teising | 0 | 0 | 0 | 73 | 200 | 0 | 179 | 280 | 0 |
| Töging a. Inn | 0 | 0 | 0 | 0 | 10 | 0 | 2 | 30 | 0 |
| Tüßling | 0 | 0 | 0 | 1346 | 1070 | 0 | 3689 | 1570 | 0 |
| Unterneukirchen | 0 | 0 | 1 | 6 | 30 | 40 | 72 | 30 | 60 |
| Winhöring | 0 | 0 | 0 | 22 | 0 | 0 | 88 | 260 | 0 |

### Notable Observations

- **Altötting HQ100:** Own analysis (996) aligns well with BfG 2019 (910). The current BfG portal shows 0, confirming incomplete data in the 3rd cycle.
- **Tüßling HQ100:** Own analysis (1346) vs. BfG 2019 (1070) — reasonable agreement given the different population data vintage (2022 census vs. ~2019 estimates).
- **Reischach shows large deviations:** Own analysis estimates 925 for HQ100, while both BfG sources show only 10. This warrants further investigation — it may indicate differences in which watercourses are included in the flood modeling.
- **Some values are higher than Version 1, some lower:** This is expected. Where residential areas are concentrated in flood zones, the refined method counts more people (smaller denominator). Where residential areas are outside flood zones, it counts fewer.

---

## SQL for the Final Comparison

All three flood scenarios, plus both BfG reference datasets, combined in one query starting from the municipality table to ensure completeness:

```sql
SELECT adm.name_3 AS gemeinde,
       r.betroffene_haeufig, 
       COALESCE(a.hq_haeufig::integer, 0)  AS bfg_2019_haeufig,
       COALESCE(b.bfg_haeufig::integer, 0) AS bfg_aktuell_haeufig,
       r.betroffene_100,
       COALESCE(a.hq_100::integer, 0)      AS bfg_2019_100,
       COALESCE(b.bfg_hq100::integer, 0)   AS bfg_aktuell_100,
       r.betroffene_extrem,
       COALESCE(a.hq_extrem::integer, 0)   AS bfg_2019_extrem,
       COALESCE(b.bfg_extrem::integer, 0)  AS bfg_aktuell_extrem
FROM adm_adm_3 adm --contains district and municipality names and geographies
LEFT JOIN result_alkis r ON adm.name_3 = r.gemeinde
LEFT JOIN bfg_betroffene_2019 a ON adm.name_3 LIKE '%' || a.gemeinde || '%'
LEFT JOIN bfg_referenz b ON adm.name_3 LIKE '%' || b.gemeinde || '%'
WHERE adm.name_2 LIKE '%Altötting%'
ORDER BY adm.name_3;
```

Starting from `adm_adm_3` and using `LEFT JOIN` ensures all municipalities appear even if they have no affected residents in any scenario. `COALESCE` fills gaps with 0 for readability.

---

## Performance Considerations

Computing `ST_Intersection` on the fly for every census cell × flood polygon × residential area combination was extremely slow. The solution was to precompute intermediate results as permanent tables:

1. **`wohnflaechen_hw_100/extrem/haeufig`** — Flood zones clipped to residential areas, one table per scenario
2. **`zensus_wohn_gesamt`** — Total residential area per census cell

The final query then performs only one spatial intersection at runtime (census cell vs. precomputed flooded residential area) and one simple ID join for the denominator. This reduced query time from over 30 minutes to under 35 seconds for all three scenarios combined.

---

## Data Sources

| Dataset | Source | Format | CRS |
|---|---|---|---|
| Hochwassergefahrenflächen HQ100, HQextrem, HQhäufig | LfU Bayern (provided on request) | Shapefile | EPSG:25832 |
| Zensus 2022 — Bevölkerung 100m-Gitter | Statistisches Bundesamt | GeoPackage | EPSG:3857 (reprojected to 25832) |
| ALKIS Tatsächliche Nutzung | Bayerische Vermessungsverwaltung | Shapefile | EPSG:25832 |
| Verwaltungsgrenzen (Gemeinden, Landkreise) | GADM / BKG | Shapefile | EPSG:4326 (reprojected to 25832) |
| BfG Hochwasserrisikokarte 2019 — Betroffene Einwohner | BfG Geoportal (2. Zyklus) | manually extracted | — |
| BfG Hochwasserrisikokarte aktuell — Betroffene Einwohner | BfG Geoportal (3. Zyklus) | manually extracted | — |

---

## Tools & Technologies

- **PostgreSQL + PostGIS** — Spatial database, all analysis performed via SQL
- **Docker** (kartoza/postgis image) — Database containerization
- **QGIS** — Data visualization and DB Manager for query development
- **GDAL** (`shp2pgsql`) — Data import and format conversion
- **VS Code** — Container setup, data import, script execution

---

## Limitations

- The 100m census grid remains the population unit. While ALKIS land use data refines *where* within the cell people are assumed to live, the actual population distribution within a cell is still unknown.
- ALKIS "Wohnbaufläche" and "Mischnutzung mit Wohnen" classifications include gardens, driveways, and other non-building areas. They are land use zones, not individual building outlines.
- The analysis considers only the 2D surface area of flood zones. Flood depth, flow velocity, and building elevation are not accounted for.
- Flood hazard polygons represent modeled scenarios, not observed events.
- The BfG comparison is limited by the availability and completeness of official data, particularly in the ongoing 3rd reporting cycle.

---

## What I Learned (Beyond SQL)

The biggest unexpected lesson from this project wasn't technical, but rather that official reference data can be ambiguous. Three different portals from the same federal agency showed three different numbers for the same municipality. Understanding *why* (reporting cycles, data vintages, incomplete uploads) turned out to be just as important as getting the SQL right.

The ALKIS refinement also taught a lesson about data resolution mismatches: building-level footprints are too fine for a 100m population grid (leading to undercounting), while land use zones are too coarse (leading to overcounting). The sweet spot was using land use zones as the denominator while accepting that the 100m grid sets the practical resolution limit.

---

## Author

gisberger (Andreas Giglberger)
