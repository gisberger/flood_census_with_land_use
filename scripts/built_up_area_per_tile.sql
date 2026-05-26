CREATE TABLE zensus_wohn_gesamt AS
SELECT z.id, SUM(ST_Area(ST_Intersection(z.geom, w.geom))) AS wohn_area
FROM zensus2022_100m z
JOIN wohnflaechen w ON ST_Intersects(z.geom, w.geom)
GROUP BY z.id;