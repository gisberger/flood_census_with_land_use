# Flood Exposure Analysis with Land Use Refinement in Landkreis Altötting, Bavaria

## What This Project Is About

This is the second iteration of my flood exposure analysis for Landkreis Altötting. The [first version](https://github.com/gisberger/flood_census) estimated affected population using a 100m census grid overlaid with flood hazard polygons and a simple area-weighting approach.

This version refines the method by incorporating ALKIS land use data containing specifically residential area classifications to distribute population more realistically. Instead of assuming people are spread uniformly across a census cell, the calculation now concentrates them in areas classified as residential, then checks how much of that residential area is flooded.

During the process, I also discovered that the BfG operates multiple flood risk map portals with different data vintages, and that the LfU Bayern publishes its own Beiblätter with yet another set of numbers — which resolved a confusing discrepancy from the first project and added a four-way comparison to the analysis.

All SQL code was hand-written, with troubleshooting support by Claude model Opus 4.7.

---

## Key Improvement Over Version 1

**Version 1 formula:**
```
Einwohner × (flooded area of cell / total cell area)
```

**Version 2 formula:**
```
Einwohner × (flooded residential area in cell / total residential area in cell)
```

The difference: if a census cell is 80% farmland and 20% residential, and the flood zone covers the residential part, Version 1 assigns only 20% of the population (because 20% of the cell is flooded). Version 2 correctly assigns ~100% (because all the residential area is flooded). Conversely, if only farmland floods, Version 2 assigns 0 — nobody lives there.

### The Double-Counting Problem

An early version of this approach produced impossibly high numbers — some municipalities showed more affected residents than total inhabitants. The cause: when multiple residential flood polygons fell within the same census cell, each one triggered a separate population calculation against the same denominator, counting the same people multiple times.

The fix was to merge (`ST_Union`) all flood-residential polygons per census cell before calculating the area ratio, ensuring each cell is counted exactly once regardless of how many individual residential or flood polygons it contains.

### Three-Tier Precomputation

The final approach uses three levels of precomputed tables to keep the runtime query fast:

**Tier 1 — Flooded residential areas** (one table per scenario): Flood zones clipped to ALKIS residential land use polygons.

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

**Tier 2 — Flooded residential area per census cell** (one table per scenario): Merges overlapping flood-residential polygons within each cell to prevent double-counting, then calculates the area.

```sql
CREATE TABLE flood_per_cell_100 AS
SELECT z.id, ST_Area(ST_Intersection(z.geom, ST_Union(f.geom))) AS flooded_wohn_area
FROM zensus2022_100m z
JOIN wohnflaechen_hw_100 f ON ST_Intersects(z.geom, f.geom)
GROUP BY z.id, z.geom;
```

**Tier 3 — Total residential area per census cell** (shared across all scenarios):

```sql
CREATE TABLE zensus_wohn_gesamt AS
SELECT z.id, SUM(ST_Area(ST_Intersection(z.geom, w.geom))) AS wohn_area
FROM zensus2022_100m z
JOIN wohnflaechen w ON ST_Intersects(z.geom, w.geom)
GROUP BY z.id;
```

The final result query then uses only ID-based joins — no spatial operations at runtime:

```sql
CREATE TABLE result_alkis AS
SELECT a.name_3 AS gemeinde,
       COALESCE(ROUND(SUM(z."Einwohner" * (hau.flooded_wohn_area / w.wohn_area))::numeric, 0), 0)::integer AS betroffene_haeufig,
       COALESCE(ROUND(SUM(z."Einwohner" * (hun.flooded_wohn_area / w.wohn_area))::numeric, 0), 0)::integer AS betroffene_100,
       COALESCE(ROUND(SUM(z."Einwohner" * (ext.flooded_wohn_area / w.wohn_area))::numeric, 0), 0)::integer AS betroffene_extrem
FROM zensus2022_100m z
JOIN zensus_wohn_gesamt w ON z.id = w.id
LEFT JOIN flood_per_cell_haeufig hau ON z.id = hau.id
LEFT JOIN flood_per_cell_100 hun ON z.id = hun.id
LEFT JOIN flood_per_cell_extrem ext ON z.id = ext.id
JOIN adm_adm_3 a ON ST_Intersects(z.geom, a.geom)
WHERE a.name_2 LIKE '%Altötting%'
AND w.wohn_area > 0
AND (hau.id IS NOT NULL OR hun.id IS NOT NULL OR ext.id IS NOT NULL)
GROUP BY a.name_3;
```

---

## The BfG Data Confusion

During the first project, I compared my results against a BfG flood risk map that showed zero affected residents for several municipalities. This seemed wrong — my analysis clearly showed residential areas within flood zones there.

It turned out that the BfG operates two separate map portals with different data:

- **HWRM 2019** (`geoportal.bafg.de/karten/HWRM/`) — The 2nd reporting cycle, ArcGIS-based layout. This version has more complete data for Landkreis Altötting.
- **HWRM current** (`geoportal.bafg.de/karten/HWRM_2026/`) — The 3rd reporting cycle, newer layout. This version shows zeros for many municipalities, likely because Bavaria's data upload for the 3rd cycle is still incomplete (reporting deadline December 2025, management plans due December 2027).

Additionally, the LfU Bayern publishes **Beiblätter** (PDF supplements) per municipality and per watercourse, containing a third set of numbers that include water depth breakdowns. These values sometimes differ from both BfG portals.

This version compares against all four sources — own analysis, BfG 2019, BfG current, and LfU Beiblätter — to give the full picture.

---

## Final Comparison Table

| Municipality | Own (freq.) | BfG 2019 (freq.) | BfG current (freq.) | LfU (freq.) | Own (HQ100) | BfG 2019 (HQ100) | BfG current (HQ100) | LfU (HQ100) | Own (extr.) | BfG 2019 (extr.) | BfG current (extr.) | LfU (extr.) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Altötting | 0 | 0 | 0 | 0 | 338 | 910 | 0 | 580 | 2879 | 2490 | 0 | 2670 |
| Burghausen | 1 | 0 | 1 | 0 | 25 | 0 | 30 | 30 | 403 | 190 | 190 | 190 |
| Burgkirchen a.d. Alz | 5 | 0 | 10 | 0 | 22 | 730 | 80 | 0 | 1403 | 0 | 1610 | 0 |
| Emmerting | 0 | 0 | 1 | 0 | 0 | 0 | 1 | 0 | 2835 | 2200 | 2660 | 2660 |
| Garching a.d. Alz | 0 | 0 | 1 | 0 | 50 | 190 | 80 | 0 | 691 | 600 | 730 | 0 |
| Haiming | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| Kirchweidach | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| Marktl | 0 | 0 | 1 | 0 | 3 | 0 | 10 | 0 | 11 | 0 | 20 | 30 |
| Neuötting | 0 | 0 | 20 | 20 | 326 | 450 | 40 | 440 | 1802 | 1560 | 1710 | 1710 |
| Pleiskirchen | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| Reischach | 3 | 0 | 1 | 0 | 73 | 10 | 10 | 10 | 149 | 30 | 30 | 30 |
| Teising | 0 | 0 | 0 | 0 | 28 | 200 | 0 | 70 | 109 | 280 | 0 | 250 |
| Töging a. Inn | 0 | 0 | 0 | 0 | 0 | 10 | 0 | 0 | 2 | 30 | 0 | 0 |
| Tüßling | 0 | 0 | 0 | 0 | 421 | 1070 | 0 | 410 | 1923 | 1570 | 0 | 1620 |
| Unterneukirchen | 0 | 0 | 1 | 0 | 6 | 30 | 40 | 40 | 72 | 30 | 60 | 60 |
| Winhöring | 0 | 0 | 0 | 0 | 9 | 0 | 0 | 0 | 64 | 260 | 0 | 60 |

### Notable Observations

- **Tüßling HQ100:** Own analysis (421) vs. LfU Beiblatt (410) — remarkably close, suggesting the ALKIS-refined method produces results comparable to the official LfU methodology for this municipality.
- **Emmerting extreme:** Own analysis (2835) vs. BfG 2019 (2200) vs. BfG current (2660) vs. LfU (2660). The BfG current and LfU values agree, and the own analysis is in the same range.
- **Neuötting HQ100:** Own analysis (326) vs. BfG 2019 (450) vs. LfU (440). Consistent underestimation by the own analysis — possibly due to residential areas just outside the ALKIS classification that the official method captures.
- **Altötting HQ100:** Own analysis (338) vs. BfG 2019 (910) vs. LfU (580). Significant spread across all sources, suggesting genuine uncertainty or differences in which watercourses are modeled.
- **Reischach and Teising** show large deviations between own analysis and all official sources, warranting further investigation into which flood polygons cover those municipalities.
- **BfG current portal** continues to show zeros for many municipalities where all other sources agree on significant exposure, confirming incomplete data in the 3rd reporting cycle.

---

## SQL for the Final Comparison

All three flood scenarios, plus three official reference datasets, combined in one query starting from the municipality table to ensure completeness:

```sql
SELECT adm.name_3 AS gemeinde,
       r.betroffene_haeufig, 
       COALESCE(a.hq_haeufig::integer, 0)  AS bfg_2019_haeufig,
       COALESCE(b.bfg_haeufig::integer, 0) AS bfg_aktuell_haeufig,
       COALESCE(l.lfu_haeufig::integer, 0) AS lfu_haeufig,
       r.betroffene_100,
       COALESCE(a.hq_100::integer, 0)      AS bfg_2019_100,
       COALESCE(b.bfg_hq100::integer, 0)   AS bfg_aktuell_100,
       COALESCE(l.lfu_100::integer, 0)     AS lfu_100,
       r.betroffene_extrem,
       COALESCE(a.hq_extrem::integer, 0)   AS bfg_2019_extrem,
       COALESCE(b.bfg_extrem::integer, 0)  AS bfg_aktuell_extrem,
       COALESCE(l.lfu_extrem::integer, 0)  AS lfu_extrem
FROM adm_adm_3 adm
LEFT JOIN result_alkis r ON adm.name_3 = r.gemeinde
LEFT JOIN bfg_betroffene_2019 a ON adm.name_3 LIKE '%' || a.gemeinde || '%'
LEFT JOIN bfg_referenz b ON adm.name_3 LIKE '%' || b.gemeinde || '%'
LEFT JOIN lfu_beiblatt l ON adm.name_3 LIKE '%' || l.gemeinde || '%'
WHERE adm.name_2 LIKE '%Altötting%'
ORDER BY adm.name_3;
```

Starting from `adm_adm_3` and using `LEFT JOIN` ensures all municipalities appear even if they have no affected residents in any scenario. `COALESCE` fills gaps with 0 for readability.

---

## Performance Considerations

Computing `ST_Intersection` on the fly for every census cell × flood polygon × residential area combination was prohibitively slow (30+ minutes). The three-tier precomputation approach solved this:

1. **Tier 1 — `wohnflaechen_hw_*`** — Flood zones clipped to residential areas (one table per scenario, computed once)
2. **Tier 2 — `flood_per_cell_*`** — Flooded residential area per census cell, with `ST_Union` to merge overlapping polygons and prevent double-counting (one table per scenario, computed once)
3. **Tier 3 — `zensus_wohn_gesamt`** — Total residential area per census cell (shared across scenarios, computed once)

The final result query joins everything on cell IDs — only one spatial operation remains (the Gemeinde assignment via `ST_Intersects`). Total runtime for all three scenarios combined: under 35 seconds.

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
| LfU Beiblätter — Betroffene Einwohner | LfU Bayern (PDF per municipality) | manually extracted | — |

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
- The four-way comparison reveals that even official sources disagree significantly, making it difficult to identify a single "correct" reference value.
- Some municipalities (Reischach, Teising) show persistent large deviations from all official sources, suggesting possible differences in which watercourses or flood scenarios are included in the LfU data provided for this analysis.

---

## What I Learned (Beyond SQL)

The biggest unexpected lesson from this project wasn't technical but rather discovering that official reference data can be contradictory. Four different sources (BfG 2019, BfG current, LfU Beiblätter, and my own analysis) produced four different numbers for the same municipality. Understanding *why* — reporting cycles, data vintages, incomplete uploads, different watercourse coverage — turned out to be just as important as getting the SQL right.

The ALKIS refinement taught a lesson about data resolution mismatches: building-level footprints are too fine for a 100m population grid (leading to undercounting), while land use zones are appropriately scaled. And the double-counting bug — where overlapping residential flood polygons within a single census cell inflated results beyond the total population — was a reminder that spatial joins can multiply data in ways that aren't immediately obvious.

---

## Author

gisberger (Andreas Giglberger)
