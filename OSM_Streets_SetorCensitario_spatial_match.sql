
--Mathcing osm_streets to Setor Censitario Polygons. 
  -- Because Setor Censitario polygons can have some problems, shifted sideways, etc, I used a  0.0005 decimal degrees buffer (+or- 56m) around the polygons
CREATE TABLE OSM_Streets_by_SetorCensitario AS
SELECT osm_id, cd_geocodi as cod_setor
FROM OSM_Streets_by_mun
INNER JOIN  setor_censitarioL2
ON 	OSM_Streets_by_mun.cod_mun=setor_censitarioL2.cod_mun AND
	ST_DWithin(way,geom,0.0005);
-- runs in 1h36



---------------------------------------------


select* from OSM_Streets_by_SetorCensitario limit 2000    

create table OSM_Streets_by_SetorCensitario AS SELECT * from OSM_Streets_by_SetorCensitarioA
drop table OSM_Streets_by_SetorCensitarioA

SELECT N, count(*)
FROM
	(SELECT osm_id, count(*) as N
	FROM OSM_Streets_by_SetorCensitario
	GROUP BY osm_id) AS foo
GROUP BY N
ORDER BY count(*) desc



Re run with smaller buffer. 





--Experimenting with different buffers (based on code baed on G) = Matching with municipal code and ST_DWithin

EXPLAIN
create table OSM_Streets_by_SetorCensitario_005 as select * from OSM_Streets_by_SetorCensitario







select count(*) from OSM_Streets_by_SetorCensitario  -- 5116195
-- eliminando duplicatas sao                            5044154 



CREATE TABLE  sectors_by_osm_id AS
SELECT osm_id, count(*)  AS No_setores, array_agg(cod_setor)
FROM (	select osm_id , cod_setor , count(*) AS N from OSM_Streets_by_SetorCensitario
	group by osm_id , cod_setor ) AS foo 
GROUP BY osm_id

select No_setores, count(*)
from sectors_by_osm_id  
group by No_setores
order by count(*) desc

select * from sectors_by_osm_id    limit 2000-- 5116195

select * from OSM_Streets_by_SetorCensitario   limit 2000-- 5116195

 
-- 5.1 million rows, 1h37min. Query returned successfully: 5116195 rows affected, 5822001 ms execution time.

-- To do latter Even better will be to have the buffer proportional to the distortion found in each street (by matching OSM to CNEFE and selecting fcnefe sectors with all blocks mateched))




-- grouping OSM-streets by setor
select substring(cod_setor,1,7) AS cod_mun, osm_id, count(cod_setor) as N_setores, array_agg(cod_setor)
FROM OSM_Streets_by_SetorCensitario
GROUP BY substring(cod_setor,1,7), osm_id

select * from setor_censitarioL2 limit 2000


drop table temp3


-- agregate CNEFE streets by setor
CREATE TABLE temp3 AS
SELECT 	substring(cod_setor,1,7) AS cod_mun, logradouro.idn_logradouro, 
	tipo_logradouro.dsc_tipo_logradouro, logradouro.dsc_titulo_logradouro, logradouro.nme_logradouro,
	trim(concat_ws(' ',tipo_logradouro.dsc_tipo_logradouro,logradouro.dsc_titulo_logradouro,logradouro.nme_logradouro)) AS nomeC_logradouro, 
	array_agg(cod_setor), ST_Union(geom) AS geom
FROM cnefe2010.setor
	INNER JOIN setor_censitarioL2 
	ON substring(setor.cod_setor,1,7) = setor_censitarioL2.cd_geocodm
	INNER JOIN cnefe2010.quadra 
		ON cnefe2010.setor.idn_setor = cnefe2010.quadra.idn_setor
	INNER JOIN cnefe2010.face 
		ON cnefe2010.quadra.idn_quadra = cnefe2010.face.idn_quadra 
	INNER JOIN cnefe2010.face_tem_logradouros 
		ON cnefe2010.face.idn_face = cnefe2010.face_tem_logradouros.idn_face
	INNER JOIN cnefe2010.logradouro
		ON cnefe2010.face_tem_logradouros.idn_logradouro=cnefe2010.logradouro.idn_logradouro
	INNER JOIN cnefe2010.tipo_logradouro
		ON cnefe2010.logradouro.idn_tipo_logradouro = cnefe2010.tipo_logradouro.idn_tipo_logradouro 
WHERE substring(cod_setor, 1,7) = '3550308'
GROUP BY substring(cod_setor,1,7), logradouro.idn_logradouro, 
	tipo_logradouro.dsc_tipo_logradouro, logradouro.dsc_titulo_logradouro, logradouro.nme_logradouro,
	nomeC_logradouro 

-- select only streets that are matched to setors that are countigous

SELECT ST_GeometryType(geom), count(*) 
from temp3 
GROUP BY ST_GeometryType(geom) 
ORDER BY count(*) desc





HAVING ST_Union(geom)



