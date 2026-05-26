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
	   
FROM adm_adm_3 adm
LEFT JOIN result_alkis r ON adm.name_3 = r.gemeinde
LEFT JOIN bfg_betroffene_2019 a ON adm.name_3 LIKE '%' || a.gemeinde || '%'
LEFT JOIN bfg_referenz b ON adm.name_3 LIKE '%' || b.gemeinde || '%'

WHERE adm.name_2 LIKE '%Altötting%'

ORDER BY adm.name_3;







