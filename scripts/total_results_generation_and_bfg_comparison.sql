CREATE TABLE result_alkis AS

SELECT a.name_3 AS gemeinde,

COALESCE(ROUND(SUM(z."Einwohner" * (ST_Area(ST_Intersection(z.geom, hau.geom)) / w.wohn_area))::numeric, 0), 0)::integer AS betroffene_haeufig,
COALESCE(ROUND(SUM(z."Einwohner" * (ST_Area(ST_Intersection(z.geom, hun.geom)) / w.wohn_area))::numeric, 0), 0)::integer AS betroffene_100,

COALESCE(ROUND(SUM(z."Einwohner" * (ST_Area(ST_Intersection(z.geom, ext.geom)) / w.wohn_area))::numeric, 0), 0)::integer AS betroffene_extrem  

FROM zensus2022_100m z

FULL OUTER JOIN wohnflaechen_hw_100 hun ON ST_Intersects(z.geom, hun.geom)

FULL OUTER JOIN wohnflaechen_hw_extrem ext ON ST_Intersects(z.geom, ext.geom)

FULL OUTER JOIN wohnflaechen_hw_haeufig hau ON ST_Intersects(z.geom, hau.geom)


JOIN zensus_wohn_gesamt w ON z.id = w.id

JOIN adm_adm_3 a ON ST_Intersects(z.geom, a.geom)

WHERE a.name_2 LIKE '%Altötting%'

AND NOT (w.wohn_area = 0)

GROUP BY a.name_3;

SELECT r.gemeinde,
       r.betroffene_haeufig, 
	   COALESCE(a.hq_haeufig::integer, 0)  AS gfb_2019_haeufig,
       COALESCE(b.bfg_haeufig::integer, 0) AS gfb_aktuell_haeufig,
       r.betroffene_100,
       COALESCE(a.hq_100::integer, 0)      AS gfb_2019_100,
       COALESCE(b.bfg_hq100::integer, 0)   AS gfb_aktuell_100,
       r.betroffene_extrem,
       COALESCE(a.hq_extrem::integer, 0)   AS gfb_2019_extrem,
       COALESCE(b.bfg_extrem::integer, 0)  AS gfb_aktuell_extrem
FROM result_alkis r
LEFT JOIN bfg_betroffene_2019 a ON r.gemeinde LIKE '%' || a.gemeinde || '%'
LEFT JOIN bfg_referenz b ON r.gemeinde LIKE '%' || b.gemeinde || '%'

ORDER BY r.gemeinde;







