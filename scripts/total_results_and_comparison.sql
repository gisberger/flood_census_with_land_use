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
	   COALESCE(alt.haeufig, 0)::integer AS alt_haeufig,
       r.betroffene_100, 
	   COALESE(alt.hq100, 0):: integer AS alt_100,
       r.betroffene_extrem, 
	   COALESCE(alt.extrem, 0)::integer AS alt_extrem
FROM result_alkis r
LEFT JOIN result_combined alt ON r.gemeinde = alt.gemeinde
ORDER BY r.gemeinde;



