SELECT a.name_3 AS gemeinde,
       ROUND(SUM(z."Einwohner"), 0) AS betroffene
FROM zensus2022_100m z
JOIN 
(
SELECT DISTINCT h.geom
FROM hwgfhq100_15_04_2026 h 
JOIN nutzung_aoe n ON st_intersects(n.geom, h.geom)
WHERE (n.bez LIKE '%Gebäude- und Freifläche Mischnutzung mit Wohnen§' OR
n.nutzart LIKE '%Wohnbaufläche%')
) h 
ON ST_Intersects(h.geom, z.geom)
JOIN adm_adm_3 a ON ST_Intersects(z.geom, a.geom)
WHERE a.name_2 LIKE '%Altötting%'
GROUP BY a.name_3;