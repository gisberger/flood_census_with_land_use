# Flood Exposure Analysis with Land Use Refinement in Landkreis Altötting, Bavaria
 
## What This Project Is About
 
This is the second iteration of my flood exposure analysis for Landkreis Altötting. The [first version](https://github.com/gisberger/flood_census) estimated affected population using a 100m census grid overlaid with flood hazard polygons and a simple area-weighting approach.
 
This version refines the method by incorporating ALKIS land use data containing specifically residential area classifications to distribute population more realistically. Instead of assuming people are spread uniformly across a census cell, the calculation now concentrates them in areas classified as residential, then checks how much of that residential area is flooded.
 
During the process, I also pulled in the BfG's current flood risk portal figures and the LfU Bayern's own Beiblätter as two independent official reference datasets, which added a three-way comparison to the analysis. An early extraction issue on my end briefly made it look like the BfG portal had incomplete data for several municipalities - after fixing it, BfG current turned out to agree closely with LfU almost everywhere.
 
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
 
The difference: if a census cell is 80% farmland and 20% residential, and the flood zone covers the residential part, Version 1 assigns only 20% of the population (because 20% of the cell is flooded). Version 2 correctly assigns ~100% (because all the residential area is flooded). Conversely, if only farmland floods, Version 2 assigns 0 - nobody lives there.
 
### The Double-Counting Problem
 
An early version of this approach produced impossibly high numbers - some municipalities showed more affected residents than total inhabitants. The cause: when multiple residential flood polygons fell within the same census cell, each one triggered a separate population calculation against the same denominator, counting the same people multiple times.
 
The fix was to merge (`ST_Union`) all flood-residential polygons per census cell before calculating the area ratio, ensuring each cell is counted exactly once regardless of how many individual residential or flood polygons it contains.
 
### Three-Tier Precomputation
 
The final approach uses three levels of precomputed tables to keep the runtime query fast:
 
**Tier 1 - Flooded residential areas** (one table per scenario): Flood zones clipped to ALKIS residential land use polygons.
 
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
 
**Tier 2 - Flooded residential area per census cell** (one table per scenario): Merges overlapping flood-residential polygons within each cell to prevent double-counting, then calculates the area.
 
```sql
CREATE TABLE flood_per_cell_100 AS
SELECT z.id, ST_Area(ST_Intersection(z.geom, ST_Union(f.geom))) AS flooded_wohn_area
FROM zensus2022_100m z
JOIN wohnflaechen_hw_100 f ON ST_Intersects(z.geom, f.geom)
GROUP BY z.id, z.geom;
```
 
**Tier 3 - Total residential area per census cell** (shared across all scenarios):
 
```sql
CREATE TABLE zensus_wohn_gesamt AS
SELECT z.id, SUM(ST_Area(ST_Intersection(z.geom, w.geom))) AS wohn_area
FROM zensus2022_100m z
JOIN wohnflaechen w ON ST_Intersects(z.geom, w.geom)
GROUP BY z.id;
```
 
The final result query then uses only ID-based joins - no spatial operations at runtime:
 
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
 
During the first project, I compared my results against the BfG's current flood risk map (HWRM current, 3rd reporting cycle, `geoportal.bafg.de/karten/HWRM_2026/`), which initially showed zero affected residents for several municipalities. This seemed wrong - my analysis clearly showed residential areas within flood zones there.
 
My first assumption was that Bavaria's data upload for the 3rd reporting cycle (deadline December 2025, management plans due December 2027) was still incomplete. After re-extracting the BfG figures more carefully, though, the zeros turned out to be an artifact of my own extraction process rather than a genuine gap in the portal's data - once corrected, BfG current numbers are identical or nearly identical to the LfU Beiblätter in almost every municipality.
 
Additionally, the LfU Bayern publishes **Beiblätter** (PDF supplements) per municipality and per watercourse, containing a separate set of numbers that include water depth breakdowns.
 
This version compares against three sources - own analysis, BfG current, and LfU Beiblätter. With the two official sources now largely corroborating each other (with a couple of small exceptions), the more informative comparison is between the official sources together and my own ALKIS-refined analysis, which diverges meaningfully in several municipalities - see below.
 
---
 
## Final Comparison Table
 
| Municipality | Own (freq.) | BfG current (freq.) | LfU (freq.) | Own (HQ100) | BfG current (HQ100) | LfU (HQ100) | Own (extr.) | BfG current (extr.) | LfU (extr.) |
|---|---|---|---|---|---|---|---|---|---|
| Altötting | 0 | 0 | 0 | 338 | 540 | 580 | 2879 | 2630 | 2670 |
| Burghausen | 1 | 1 | 0 | 25 | 30 | 30 | 403 | 190 | 190 |
| Burgkirchen a.d. Alz | 5 | 10 | 10 | 22 | 80 | 80 | 1403 | 1610 | 1610 |
| Emmerting | 0 | 1 | 0 | 0 | 1 | 0 | 2835 | 2660 | 2660 |
| Garching a.d. Alz | 0 | 1 | 0 | 50 | 80 | 80 | 691 | 730 | 730 |
| Haiming | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 1 | 0 |
| Kirchweidach | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| Marktl | 0 | 1 | 0 | 3 | 10 | 0 | 11 | 20 | 30 |
| Neuötting | 0 | 20 | 20 | 326 | 440 | 440 | 1802 | 1710 | 1710 |
| Pleiskirchen | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| Reischach | 3 | 1 | 0 | 73 | 10 | 10 | 149 | 30 | 30 |
| Teising | 0 | 0 | 0 | 28 | 70 | 70 | 109 | 250 | 250 |
| Töging a. Inn | 0 | 0 | 0 | 0 | 10 | 10 | 2 | 30 | 30 |
| Tüßling | 0 | 0 | 0 | 421 | 410 | 410 | 1923 | 1620 | 1620 |
| Unterneukirchen | 0 | 1 | 0 | 6 | 40 | 40 | 72 | 60 | 60 |
| Winhöring | 0 | 0 | 0 | 9 | 10 | 0 | 64 | 60 | 60 |
 
### Notable Observations
 
- **BfG current and LfU agree almost everywhere.** Across nearly every municipality and scenario, the two official sources are identical or within a few people of each other. The zeros I initially saw in the BfG portal turned out to be an extraction issue on my end, not incomplete 3rd-cycle data as first assumed - the same underlying lesson as the Garching/Burgkirchen name-matching bug below. With the officials agreeing this closely, the interesting comparison is now own analysis vs. the official consensus, not official-vs-official.
- **Reischach** shows the largest divergence in the dataset: own analysis (73 / 149) runs roughly 5-7× higher than both official sources (10 / 30) for HQ100 and extreme. Worth investigating which flood polygons are included here - possibly own analysis is capturing a watercourse or residential area the official sources exclude.
- **Töging a. Inn and Unterneukirchen (HQ100)** show the opposite pattern: own analysis (0 and 6) comes in well below both official sources (10 and 40), suggesting the ALKIS residential classification may be missing some affected buildings in these municipalities.
- **Tüßling HQ100** is the closest match in the dataset: own analysis (421) vs. both official sources (410) - a gap of just 11, suggesting the ALKIS-refined method can track the official methodology closely when watercourse coverage lines up.
- **Marktl and Winhöring (HQ100)** are the only cases where BfG current and LfU disagree with each other (10 vs. 0 in both) rather than own analysis being the outlier - worth keeping in mind that "official" doesn't always mean "single-valued."
- **Garching a.d. Alz and Burgkirchen a.d. Alz:** an earlier version of this table had a name-matching bug where these two municipalities - both containing the token "Alz" - were briefly joined to the same LfU source row. After fixing the join to require exact token-set matches instead of partial overlap, both municipalities' LfU and BfG current figures now agree with each other, with own analysis coming in lower for both (Garching: 50/691 vs. 80/730 official; Burgkirchen: 22/1403 vs. 80/1610 official). The view below shows only a small residential footprint actually falling within Burgkirchen's flood extent, which may explain why own analysis lands lower here.
<img width="829" height="546" alt="image" src="https://github.com/user-attachments/assets/3496991b-0d59-4842-952e-4cb64a7d4793" />
---
 
## SQL for the Final Comparison
 
All three flood scenarios, plus the two official reference datasets, combined in one query starting from the municipality table to ensure completeness:
 
```sql
SELECT adm.name_3 AS gemeinde,
       r.betroffene_haeufig,
       COALESCE(b.bfg_haeufig::integer, 0) AS bfg_aktuell_haeufig,
       COALESCE(l.lfu_haeufig::integer, 0) AS lfu_haeufig,
       r.betroffene_100,
       COALESCE(b.bfg_hq100::integer, 0)   AS bfg_aktuell_100,
       COALESCE(l.lfu_100::integer, 0)     AS lfu_100,
       r.betroffene_extrem,
       COALESCE(b.bfg_extrem::integer, 0)  AS bfg_aktuell_extrem,
       COALESCE(l.lfu_extrem::integer, 0)  AS lfu_extrem
FROM adm_adm_3 adm
LEFT JOIN result_alkis r ON adm.name_3 = r.gemeinde
LEFT JOIN bfg_referenz b ON adm.name_3 LIKE '%' || b.gemeinde || '%'
LEFT JOIN lfu_beiblatt l ON adm.name_3 LIKE '%' || l.gemeinde || '%'
WHERE adm.name_2 LIKE '%Altötting%'
ORDER BY adm.name_3;
```
 
Starting from `adm_adm_3` and using `LEFT JOIN` ensures all municipalities appear even if they have no affected residents in any scenario. `COALESCE` fills gaps with 0 for readability.
 
> **Note:** this join still uses `LIKE '%' || gemeinde || '%'` partial-string matching, which is exactly the pattern that caused the Garching/Burgkirchen mix-up above. It works here because no two gemeinde names happen to collide anymore, but a token-based exact match (splitting each name into words and comparing sets) is safer and worth carrying over into future versions of this query.
 
---
 
## Performance Considerations
 
Computing `ST_Intersection` on the fly for every census cell × flood polygon × residential area combination was prohibitively slow (30+ minutes). The three-tier precomputation approach solved this:
 
1. **Tier 1 - `wohnflaechen_hw_*`** - Flood zones clipped to residential areas (one table per scenario, computed once)
2. **Tier 2 - `flood_per_cell_*`** - Flooded residential area per census cell, with `ST_Union` to merge overlapping polygons and prevent double-counting (one table per scenario, computed once)
3. **Tier 3 - `zensus_wohn_gesamt`** - Total residential area per census cell (shared across scenarios, computed once)
The final result query joins everything on cell IDs - only one spatial operation remains (the Gemeinde assignment via `ST_Intersects`). Total runtime for all three scenarios combined: under 35 seconds.
 
---
 
## Data Sources
 
| Dataset | Source | Format | CRS |
|---|---|---|---|
| Hochwassergefahrenflächen HQ100, HQextrem, HQhäufig | LfU Bayern (provided on request) | Shapefile | EPSG:25832 |
| Zensus 2022 - Bevölkerung 100m-Gitter | Statistisches Bundesamt | GeoPackage | EPSG:3857 (reprojected to 25832) |
| ALKIS Tatsächliche Nutzung | Bayerische Vermessungsverwaltung | Shapefile | EPSG:25832 |
| Verwaltungsgrenzen (Gemeinden, Landkreise) | GADM / BKG | Shapefile | EPSG:4326 (reprojected to 25832) |
| BfG Hochwasserrisikokarte aktuell - Betroffene Einwohner | BfG Geoportal (3. Zyklus) | manually extracted | - |
| LfU Beiblätter - Betroffene Einwohner | LfU Bayern (PDF per municipality) | manually extracted | - |
 
---
 
## Tools & Technologies
 
- **PostgreSQL + PostGIS** - Spatial database, all analysis performed via SQL
- **Docker** (kartoza/postgis image) - Database containerization
- **QGIS** - Data visualization and DB Manager for query development
- **GDAL** (`shp2pgsql`) - Data import and format conversion
- **VS Code** - Container setup, data import, script execution
---
 
## Limitations
 
- The 100m census grid remains the population unit. While ALKIS land use data refines *where* within the cell people are assumed to live, the actual population distribution within a cell is still unknown.
- ALKIS "Wohnbaufläche" and "Mischnutzung mit Wohnen" classifications include gardens, driveways, and other non-building areas. They are land use zones, not individual building outlines.
- The analysis considers only the 2D surface area of flood zones. Flood depth, flow velocity, and building elevation are not accounted for.
- Flood hazard polygons represent modeled scenarios, not observed events.
- BfG current and LfU agree closely in almost every municipality, with Marktl and Winhöring (HQ100) as the only real exceptions - so in most cases there is a reliable official consensus to compare own analysis against, though not a universal one.
- Some municipalities (Reischach, Töging a. Inn, Unterneukirchen) show persistent large deviations between own analysis and the official consensus, suggesting possible differences in which watercourses or residential areas are captured by each method.
- Municipality-name joins via partial string matching (`LIKE '%name%'`) can silently produce wrong or duplicated results when names share a substring, as happened with Garching a.d. Alz and Burgkirchen a.d. Alz here. Token-based exact matching is a more robust approach for this kind of join.
---
 
## What I Learned (Beyond SQL)
 
The biggest unexpected lesson from this project wasn't technical but rather discovering how easy it is to misdiagnose a data problem. My first instinct when BfG current showed zeros for several municipalities was to blame incomplete government data upload - a plausible-sounding explanation that turned out to be wrong. The real cause was an extraction issue on my end, and once fixed, BfG current turned out to track LfU closely almost everywhere. The Garching/Burgkirchen name-matching bug was the same lesson from a different angle: an apparent data anomaly that was actually a join bug in my own pipeline. Two different bugs, same takeaway - rule out your own pipeline before concluding the official source is at fault.
 
The ALKIS refinement taught a lesson about data resolution mismatches: building-level footprints are too fine for a 100m population grid (leading to undercounting), while land use zones are appropriately scaled. And the double-counting bug - where overlapping residential flood polygons within a single census cell inflated results beyond the total population - was a reminder that spatial joins can multiply data in ways that aren't immediately obvious.
 
---
 
## Author
 
gisberger (Andreas Giglberger)
