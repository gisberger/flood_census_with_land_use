CREATE TABLE wohnflaechen_hw_100 AS
SELECT ST_Intersection(h.geom, n.geom) AS geom
FROM hwgfhq100_15_04_2026 h 
JOIN nutzung_aoe n ON ST_Intersects(n.geom, h.geom)
JOIN adm_adm_2 a ON ST_Intersects(h.geom, a.geom)
WHERE a.name_2 LIKE '%Altötting%'
AND (n.bez LIKE '%Gebäude- und Freifläche Mischnutzung mit Wohnen§' OR
n.nutzart LIKE '%Wohnbaufläche%');

CREATE TABLE wohnflaechen_hw_extrem AS
SELECT ST_Intersection(h.geom, n.geom) AS geom
FROM hwgfhqextrem_15_04_2026 h 
JOIN nutzung_aoe n ON ST_Intersects(n.geom, h.geom)
JOIN adm_adm_2 a ON ST_Intersects(h.geom, a.geom)
WHERE a.name_2 LIKE '%Altötting%'
AND (n.bez LIKE '%Gebäude- und Freifläche Mischnutzung mit Wohnen§' OR
n.nutzart LIKE '%Wohnbaufläche%');

CREATE TABLE wohnflaechen_hw_haeufig AS
SELECT ST_Intersection(h.geom, n.geom) AS geom
FROM hwgfhqhaeufig_15_04_2026 h 
JOIN nutzung_aoe n ON ST_Intersects(n.geom, h.geom)
JOIN adm_adm_2 a ON ST_Intersects(h.geom, a.geom)
WHERE a.name_2 LIKE '%Altötting%'
AND (n.bez LIKE '%Gebäude- und Freifläche Mischnutzung mit Wohnen§' OR
n.nutzart LIKE '%Wohnbaufläche%');