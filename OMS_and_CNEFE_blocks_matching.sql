﻿-- This file documents how to match OSM and CNEFE data. 
-- This involves:
--	(a) creating OSM "city blocks", which are formed defined as polygons formed by existing OSM streets. For each block I define a field with an array containing the names of its neighboring streets.
--	(b) modifying the CNEFE structure so that blocks table also contains an array with the names of neighboring streets
--	(c) matching OSM "city blocks" (a) to CNEFE city blocks (b) on the streets names array.
-- Bellow I describe each step in more detail 


--------------------------------
-- AUXILIARY FUNCTIONS:

CREATE OR REPLACE FUNCTION retira_acentuacao(p_texto text)  
  RETURNS text AS  
  $BODY$  
  Select translate($1,  
  'áàâãäåaaaÁÂÃÄÅAAAÀéèêëeeeeeEEEÉEEÈìíîïìiiiÌÍÎÏÌIIIóôõöoooòÒÓÔÕÖOOOùúûüuuuuÙÚÛÜUUUUçÇñÑýÝ',
  'aaaaaaaaaAAAAAAAAAeeeeeeeeeEEEEEEEiiiiiiiiIIIIIIIIooooooooOOOOOOOOuuuuuuuuUUUUUUUUcCnNyY'
  );  
  $BODY$  
LANGUAGE sql VOLATILE  
COST 100; 


--------------------------------
-- A) creting OSM "city blocks":

--1) select only streets in OSM
CREATE TABLE OSM_streets AS
SELECT * 
FROM planet_osm_line
WHERE
    (highway='living_street' or highway='motorway' or highway='primary' or highway='proposed' or highway='raceway' or 
    highway='residential' or highway='road' or highway='secondary' or highway='tertiary' or 
    highway='track' or 
    highway='trunk' or highway='unclassified' or route='road');
CREATE INDEX OSM_streets_index ON OSM_streets USING gist  (way);
CLUSTER OSM_Streets using OSM_Streets_index;

/* Here selection the createria to select roads, or other line types that define bocks could be refined. An alternative could be
    line.highway NOT IN ('construction', 'footway', 'path', 'steps', 'track', 'cycleway', 'pedestrian', 'abandoned',
    'disused') AND 
    (line.service NOT IN ('parking_aisle', 'driveway') OR line.service is null) AND (line.access NOT IN ('no', 'private') or    line.access is null) AND
Let me know if you have a more precise way to identify streets. 
*/


--2) match OSM_streets to the IBGE state and municipality and Enumeration districs (setor censitario) layers

--2a) municipality match
CREATE TABLE OSM_Streets_by_Mun AS
SELECT cod_uf, cod_mun, OSM_Streets.*
FROM OSM_Streets, UFs_Brasil, municipios_Brasil
WHERE ST_Intersects(way,UFs_Brasil.geom) AND ST_Intersects(way,municipios_Brasil.geom);
CREATE INDEX OSM_Streets_by_Mun_index ON OSM_Streets_by_Mun USING gist  (way);
CLUSTER OSM_Streets_by_Mun using OSM_Streets_by_Mun_index;

--This is important to reduce the dimensionality of subsequent queries, constructing blocks only within municipality. OBS:Minor problem: This will lead to problems with blocks that cross municipall borders, which can occur in conurbated municipalities 


--2b) ED match
CREATE TABLE OSM_Streets_by_SetorCensitario AS
SELECT osm_id, cd_geocodi as cod_setor
FROM OSM_Streets
INNER JOIN 
	(SELECT *, ST_Buffer(geom,0.005) as geom_buffed
	FROM setor_censitarioL) AS foo
ON ST_Intersects(way,geom_buffed)



---- Find place for this.... 
-- 4b) Enumeration district level

CREATE TABLE OSM_Streets_by_SetorCensitario AS
SELECT OSM_Streets_by_Mun.*, setor_censitarioL.geom
FROM OSM_Streets_by_Mun, setor_censitarioL
WHERE 	OSM_Streets_by_Mun.cod_UF= substring(setor_censitarioL.cd_geocodi,1,2)  AND
	OSM_Streets_by_Mun.cod_mun= substring(setor_censitarioL.cd_geocodi,1,7)   AND
	ST_Intersects(way,ST_Buffer(setor_censitarioL.geom,0.005))=true

-- the above query never finishes, eventually chashin the server. 
-- I asked a question about it here http://stackoverflow.com/questions/32907481/optimize-large-st-intersect-query-match-1-8m-osm-streets-to-317k-polygons

-- Since it does not run with the 1.8 million streets  I tryed with the 480k fully named blocks I created in (OSM_blocks_fullyNamed). 
-- Also, following previous sucgestoins I pre-compute a new geom with the buffer. 


CREATE TABLE setor_censitarioL2 AS
SELECT *, ST_Buffer(geom,0.005) as geom_buffed
FROM setor_censitarioL


CREATE TABLE OSM_Streets_by_SetorCensitario AS
SELECT OSM_Streets_by_Mun.*, setor_censitarioL.geom
FROM OSM_Streets_by_Mun, setor_censitarioL
WHERE 	OSM_Streets_by_Mun.cod_UF= substring(setor_censitarioL.cd_geocodi,1,2)  AND
	OSM_Streets_by_Mun.cod_mun= substring(setor_censitarioL.cd_geocodi,1,7)   AND
	ST_Intersects(way,ST_Buffer(setor_censitarioL.geom,0.005))=true


--------


--3) Create OSM blocks for each municipality

--3a) Union all street segments into a coommon multiline geom (ST_Union() ) in each municipality

CREATE TABLE OSM_streets_mergedlines AS
SELECT cod_mun,ST_Union(way) as geom 
FROM OSM_streets_by_Mun
GROUP BY cod_mun;
CREATE INDEX OSM_streets_mergedlines_index ON OSM_streets_mergedlines USING gist  (geom);

--OBS: This generates a tale with 5538 municipalities. In the 2010 census municipal division there were 5564 municipalities. This 26 municipalities have no OSM data. 

--3b) extract all polygons formed from the unionioned streets using ST_Poligonize(). Theese are the city blocks. Notice it is necessary to Split multipoligon geom generated into a table with one poligon per line.

CREATE TABLE temp_OSM_blocks AS
SELECT cod_mun, (blocks).path[1] AS path , (blocks).geom AS geom , ST_Buffer((blocks).geom,-0.0005) AS geom2
FROM (SELECT cod_mun, ST_Dump(ST_Polygonize(geom)) AS blocks
      FROM OSM_streets_mergedlines
      GROUP BY cod_mun) AS foo;
CREATE INDEX temp_OSM_blocks_index ON temp_OSM_blocks USING gist(geom);

--4) Bring the OSM municipality and ED codes to to OSM Blocks
--Find the intersection of created polygons with the original street dataset to recover the names of the streets that carachterize each city block.

CREATE TABLE OSM_block_street_relation AS
SELECT  OSM_streets_by_mun.*, 
	temp_OSM_blocks.path,temp_OSM_blocks.geom, temp_OSM_blocks.geom2
FROM temp_OSM_blocks, OSM_streets_by_mun
WHERE   temp_OSM_blocks.cod_mun = OSM_streets_by_mun.cod_mun AND 
	ST_Intersects(temp_OSM_blocks.geom, OSM_streets_by_mun.way) AND
	GeometryType(ST_Multi(ST_Intersection(temp_OSM_blocks.geom, OSM_streets_by_mun.way)))='MULTILINESTRING';
UPDATE OSM_block_street_relation SET name=trim(name);
CREATE INDEX OSM_block_street_relation_index ON OSM_block_street_relation USING gist(geom);





--5) Create OSM_Block with street name array

CREATE TABLE OSM_blocks AS
SELECT 	cod_mun, path, geom AS geom_osm_block, geom2 AS geom2_osm_block, 
	count(*) AS No_seg,
	count(name) AS No_names,
	count(distinct name) AS No_unique_names,
	array_agg(osm_id ORDER BY upper(retira_acentuacao(name))) AS osm_id_array,
	array_agg(name ORDER BY upper(retira_acentuacao(name))) AS osm_name_array,
	array_agg(upper(retira_acentuacao(name)) ORDER BY upper(retira_acentuacao(name))) AS osm_name_semAcento_array
FROM OSM_block_street_relation
GROUP BY cod_mun, path, geom_osm_block, geom2_osm_block;	
CREATE INDEX OSM_blocks_index ON OSM_blocks USING gist(geom_osm_block);


--6) Select only OSM-Blocks that ahve all streets named

CREATE TABLE OSM_blocks_fullyNamed AS
SELECT * 
from OSM_blocks 
where No_seg=No_names AND No_seg=No_unique_names

-- OBS THis lowers the number of blocks substantially, from 1,6m blocks to 480k fully named blocks. This hapens in 97%  (= 2090838/2145264)



--------------------------------
-- B) preparing CNEFE blocks "city blocks":

--1) Creating table with blocks and street names. 
-- OBS The WHERE clause selects only CNEFE blocks with only one street name per block face. This hapens in 97%  (= 2090838/2145264) of CNEFE blocks. Only  37% (= 791539/2145264) of CNEFE blocks have 4 faces (and only 1 street name per face)


CREATE TABLE cnefe2010.aux_quadra AS
SELECT 	setor.idn_setor, setor.cod_setor, situacao_setor.idn_situacao_setor, situacao_setor.dsc_situacao_setor,
	quadra.idn_quadra, quadra.num_quadra, 
	face.idn_face, face_tem_logradouros.idn_logradouro, 
	tipo_logradouro.dsc_tipo_logradouro, logradouro.dsc_titulo_logradouro, logradouro.nme_logradouro,
	trim(concat_ws(' ',tipo_logradouro.dsc_tipo_logradouro,logradouro.dsc_titulo_logradouro,logradouro.nme_logradouro)) AS nomeC_logradouro
FROM	cnefe2010.setor
	LEFT JOIN cnefe2010.situacao_setor
		ON cnefe2010.setor.idn_situacao_setor = cnefe2010.situacao_setor.idn_situacao_setor
	LEFT JOIN cnefe2010.quadra 
		ON cnefe2010.setor.idn_setor = cnefe2010.quadra.idn_setor
	LEFT JOIN cnefe2010.face 
		ON cnefe2010.quadra.idn_quadra = cnefe2010.face.idn_quadra 

	LEFT JOIN cnefe2010.face_tem_logradouros 
		ON cnefe2010.face.idn_face = cnefe2010.face_tem_logradouros.idn_face
	LEFT JOIN cnefe2010.logradouro
		ON cnefe2010.face_tem_logradouros.idn_logradouro=cnefe2010.logradouro.idn_logradouro
	LEFT JOIN cnefe2010.tipo_logradouro
		ON cnefe2010.logradouro.idn_tipo_logradouro = cnefe2010.tipo_logradouro.idn_tipo_logradouro 
WHERE 	(quadra.idn_quadra) 
	IN (	SELECT a.idn_quadra 
		FROM  (	SELECT quadra.idn_quadra, face.idn_face , count(face_tem_logradouros.idn_logradouro) as N
			FROM 	cnefe2010.quadra  
				LEFT JOIN cnefe2010.face 
					ON cnefe2010.quadra.idn_quadra = cnefe2010.face.idn_quadra 
				LEFT JOIN cnefe2010.face_tem_logradouros 
					ON cnefe2010.face.idn_face = cnefe2010.face_tem_logradouros.idn_face
			GROUP BY quadra.idn_quadra, face.idn_face ) AS a
		GROUP BY a.idn_quadra 
		HAVING avg(a.N)=1)

--2) Collapsing the data to a CNEFE block with street name array

CREATE TABLE cnefe2010.quadra_array_ruas AS
SELECT 	substring(cod_setor,1,7) AS cod_mun, idn_setor, cod_setor, idn_situacao_setor, dsc_situacao_setor,
	idn_quadra, num_quadra, count(*) as no_faces, 
	array_agg(idn_face ORDER BY nomeC_logradouro) as array_idn_face, array_agg(nomeC_logradouro ORDER BY nomeC_logradouro) as array_nomeC_logradouro
FROM cnefe2010.aux_quadra
GROUP BY cod_mun, idn_setor, cod_setor, idn_situacao_setor, dsc_situacao_setor, idn_quadra, num_quadra




--------------------------------
-- C) Matching OSM-Blocks (A) with CNEFE-Blocks (B) based on municipality and street names of each block. 

CREATE TABLE OSM_CNEFE_block_matches AS
SELECT 	OSM_blocks_fullyNamed.cod_mun, 
	idn_setor, cod_setor, idn_situacao_setor, dsc_situacao_setor,
	idn_quadra, 
	no_faces, 
	path, No_seg, No_names, No_unique_names, osm_id_array, osm_name_array,
	geom_osm_block, geom2_osm_block
FROM cnefe2010.quadra_array_ruas, OSM_blocks_fullyNamed
where 	OSM_blocks_fullyNamed.cod_mun = quadra_array_ruas.cod_mun;
	AND osm_name_semAcento_array = array_nomeC_logradouro;


CREATE INDEX OSM_blocks_index ON OSM_blocks USING gist(geom_osm_block);


--we find 95160 block matches, located in 1822 municipios. 

-- OBS Next step should  be try a fuzzy match on the street name arrays





-------------------------
-------------------------
-------------------------
other auxiliary queries, tests, to do list (and maybe some garbage)
#aux_setor


--matched blocks that are also the full ED
SELECT count(*) 
FROM  OSM_CNEFE_block_matches
WHERE idn_setor in 
	(SELECT idn_setor 
	 FROM cnefe2010.quadra 
	 GROUP BY idn_setor
	 HAVING count(*) = 1)

SELECT cod_mun, count(*) 
FROM  OSM_CNEFE_block_matches
WHERE idn_setor in 
	(SELECT idn_setor 
	 FROM cnefe2010.quadra 
	 GROUP BY idn_setor
	 HAVING count(*) = 1)
GROUP BY cod_mun
ORDER BY count(*) desc

--312 mil setores.
-- Destes 93 mil setores tem um so quarteirao
-- Dentre estes de um so quarteirao 952 foram pareados com o OSM	 
-- Eses pareados pertencem a 81 municipios

SELECT	idn_setor, 
	count(idn_quadra),
	count(osm_id_array)
FROM cnefe2010.quadra
LEFT JOIN OSM_CNEFE_block_matches
	ON quadra.idn_quadra =  OSM_CNEFE_block_matches.idn_quadra
GROUP BY idn_setor


-- setores com todas as quadras mapeadas
SELECT cod_mun, count(*)
FROM
(SELECT  cod_mun, foo.idn_setor, 
	N_matched_blocks, N_blocks
FROM
       (SELECT cod_mun, idn_setor, 
	count(osm_id_array) AS N_matched_blocks
	FROM OSM_CNEFE_block_matches
	GROUP BY cod_mun, idn_setor ) AS foo
INNER JOIN 
       (SELECT idn_setor, count(quadra.idn_quadra) AS N_blocks
	FROM cnefe2010.quadra
	GROUP BY idn_setor  
)  AS baa
ON foo.idn_setor = baa.idn_setor
WHERE N_matched_blocks = N_blocks) as bbb
GROUP BY cod_mun
ORDER BY count(*) desc

-- 2272 setores tem todas as quadras mapeadas (isso e numero de linhas da subquery bbb, acima). 
-- que por sua vez pertencem a 207 municipios. 



-- creating table with EDs that could be matched in the ED shapefile and the agregation of OSM-Blocks. For each we ED e calculate de distance and angle between the ED shapefile and OSM

CREATE TABLE control_points_SC2OSM AS
SELECT 	cod_mun, idn_setor, cod_setor,
	setor_censitarioL.geom as geom_SC, 
	ST_Centroid(setor_censitarioL.geom) AS point_SC, 	
	ST_Union(geom_osm_block) AS geom_osm_setor, 
	ST_Centroid(ST_Union(geom_osm_block)) AS point_osm_setor, 
	ST_Distance(	ST_Centroid(setor_censitarioL.geom),
			ST_Centroid(ST_Union(geom_osm_block))   ) AS distance_SC2OSM, 
	ST_Azimuth(	ST_Centroid(setor_censitarioL.geom),
			ST_Centroid(ST_Union(geom_osm_block))   ) AS angle_SC2OSM, 
	ST_Distance(    ST_Centroid(ST_Transform(setor_censitarioL.geom,utmzone(ST_Centroid(setor_censitarioL.geom)))),
			ST_Centroid(ST_Transform(ST_Union(geom_osm_block),utmzone(ST_Centroid(ST_Union(geom_osm_block)))))   ) AS dist_M_SC2OSM							
FROM   OSM_CNEFE_block_matches
INNER JOIN setor_censitarioL
	ON OSM_CNEFE_block_matches.cod_setor = setor_censitarioL.cd_geocodi
GROUP BY cod_mun, idn_setor, cod_setor, geom_SC
HAVING  idn_setor IN
(	SELECT  foo.idn_setor 		
	FROM
	       (SELECT cod_mun, idn_setor, 
		count(osm_id_array) AS N_matched_blocks
		FROM OSM_CNEFE_block_matches
		GROUP BY cod_mun, idn_setor ) AS foo
	INNER JOIN 
	       (SELECT idn_setor, count(quadra.idn_quadra) AS N_blocks
		FROM cnefe2010.quadra
		GROUP BY idn_setor  
	)  AS baa
	ON foo.idn_setor = baa.idn_setor
	WHERE N_matched_blocks = N_blocks 
)	

-- Visual inspection of theese cases shows that is works great. However some sectors are quite different thatn they should be. I need to add a layer of comparing areas or perimeters and cutting wheen these are too diff








#Testes para diferentes filtros. 
SELECT a.idn_quadra , avg(a.N)
FROM  (	SELECT quadra.idn_quadra, face.idn_face , count(face_tem_logradouros.idn_logradouro) as N
	FROM 	cnefe2010.quadra  
		LEFT JOIN cnefe2010.face 
			ON cnefe2010.quadra.idn_quadra = cnefe2010.face.idn_quadra 
		LEFT JOIN cnefe2010.face_tem_logradouros 
			ON cnefe2010.face.idn_face = cnefe2010.face_tem_logradouros.idn_face
	GROUP BY quadra.idn_quadra, face.idn_face ) AS a
GROUP BY a.idn_quadra 
HAVING avg(a.N)=1 AND count(*)=4
2145264 rows retrieved.
2090838 rows , 97% das quadras tem todas as faces com apenas uma rua. 
2090838 rows , 97% das quadras tem todas as faces com apenas uma rua. 
 791539 rows, 37% das quadras tem 4 faces e todas as faces com apenas uma rua. 
This hapens in 97%  (= 2090838/2145264) of CNEFE blocks
Only  37% (= 791539/2145264) of CNEFE blocks have 4 faces (and only 1 street name per face)

		


CREATE TABLE OSM_Streets_by_SetorCensitario AS
SELECT cod_uf, cod_mun, cd_geocodi as cod_setor, OSM_Streets.*
FROM OSM_Streets, UFs_Brasil, municipios_Brasil, setor_censitarioL
WHERE 	ST_Intersects(way,UFs_Brasil.geom) 
	AND ST_Intersects(way,municipios_Brasil.geom)
	AND ST_Intersects(way,ST_Buffer(setor_censitarioL.geom,0.005))=true













----------------------------------------

--statistics on matched blocks
SELECT count(*) 
FROM (
SELECT 	setor.idn_setor, setor.cod_setor, situacao_setor.idn_situacao_setor, situacao_setor.dsc_situacao_setor,
	quadra.idn_quadra, quadra.num_quadra, 
	face.idn_face, 
	endereco.idn_endereco,
	domicilio.idn_domicilio
	
FROM	cnefe2010.setor
	LEFT JOIN cnefe2010.situacao_setor
		ON cnefe2010.setor.idn_situacao_setor = cnefe2010.situacao_setor.idn_situacao_setor
	LEFT JOIN cnefe2010.quadra 
		ON cnefe2010.setor.idn_setor = cnefe2010.quadra.idn_setor
	LEFT JOIN cnefe2010.face 
		ON cnefe2010.quadra.idn_quadra = cnefe2010.face.idn_quadra 
	LEFT JOIN cnefe2010.endereco 
		ON cnefe2010.face.idn_face = cnefe2010.endereco.idn_face 		
	LEFT JOIN cnefe2010.domicilio 
		ON cnefe2010.endereco.idn_endereco = cnefe2010.domicilio.idn_endereco 		
WHERE (setor.idn_setor, quadra.idn_quadra) in (SELECT idn_setor, idn_quadra FROM OSM_CNEFE_block_matches) 
) AS foo

--faces de quarteiroes mapeadas - 370mil (370213)
--enderecos mapeados - 1 milhao (1039728)  (de um total de 47 milhoes)
--domicilios mapeados - 1.7 milhao (1709243) de domicilios (de um total de 10 milhoes)

-- block matches by municipality

select cod_mun, count(*)
from OSM_CNEFE_block_matches
group by cod_mun
order by count(*) desc

select count(*)
from OSM_streets_by_mun
where cod_mun= '3550308'
group by cod_mun



/*ideias e to dos 
0) Rever importacao dos dados da tabela de Enderecos e domicilios, ambas tem apenas 11 milhoes, quando deveri ser mais para 81 milhoes. 
1) relacao entre as tabelas  - sao todas aninhadas? Rever o tipo de Join correto para usar
2) verificar se os CEPs sao aninhados nas faces de quarteirao
3) atualizar github
4) testar quatos dos quarteiroes achados sao de setores de um so quarteirao
5) rodar a query OSM vs. setor censitario. (esta muito lento)
6) pareamentos probabilisticos
*/


--criando a tabela com No de CEPs por face de quadra
CREATE TABLE cnefe2010.ceps_by_face AS
SELECT idn_setor, cod_setor, idn_situacao_setor, dsc_situacao_setor,
	idn_quadra, num_quadra, 
	idn_face, 
	cep_null,
	count(*) AS No_ceps_por_face, 
	array_agg(No_end_face_cep ORDER BY num_cep) AS array_No_end_face_cep,
	array_agg(num_cep 	  ORDER BY num_cep) AS array_ceps
FROM (
SELECT 	setor.idn_setor, setor.cod_setor, situacao_setor.idn_situacao_setor, situacao_setor.dsc_situacao_setor,
	quadra.idn_quadra, quadra.num_quadra, 
	face.idn_face, 
	num_cep, 
	num_cep IS NULL AS cep_null,
	count(*) AS No_end_face_cep
FROM	cnefe2010.setor
	LEFT JOIN cnefe2010.situacao_setor
		ON cnefe2010.setor.idn_situacao_setor = cnefe2010.situacao_setor.idn_situacao_setor
	LEFT JOIN cnefe2010.quadra 
		ON cnefe2010.setor.idn_setor = cnefe2010.quadra.idn_setor
	LEFT JOIN cnefe2010.face 
		ON cnefe2010.quadra.idn_quadra = cnefe2010.face.idn_quadra 
	LEFT JOIN cnefe2010.endereco 
		ON cnefe2010.face.idn_face = cnefe2010.endereco.idn_face 
GROUP BY setor.idn_setor, setor.cod_setor, situacao_setor.idn_situacao_setor, situacao_setor.dsc_situacao_setor,
	quadra.idn_quadra, quadra.num_quadra, 
	face.idn_face, num_cep, cep_null
) as foo
GROUP BY idn_setor, cod_setor, idn_situacao_setor, dsc_situacao_setor,
	idn_quadra, num_quadra, 
	idn_face, cep_null

--criando a tabela com estatisticas do numero de quadras com 1,2, 3... ceps
select  No_ceps_por_face, cep_null, count(*)
from cnefe2010.ceps_by_face
GROUP BY No_ceps_por_face, cep_null
ORDER BY count(*) desc, cep_null




select cep IS NULL cep_null, count(*)
from teste1.cnefe2010 
group by cep_null
#tudo nao nulo, 81550587


select num_cep IS NULL cep_null, count(*)
from cnefe2010.endereco
group by cep_null

select * from cnefe2010.endereco limit 2000



SELECT cep_null, count(*)
FROM 
(
SELECT 	idn_face, 
	num_cep, 
	num_cep IS NULL AS cep_null,
	count(*) AS No_end_face_cep
FROM	cnefe2010.endereco 
GROUP BY idn_face, num_cep, cep_null
) AS foo
GROUP BY cep_null


SELECT count(*) from cnefe2010.uf
# ERROR:  could not open file "base/7517593/12281394": Read-only file system

SELECT count(*) from cnefe2010.municipio
# ERROR:  could not open file "base/7517593/12281394": Read-only file system

SELECT count(*) from cnefe2010.distrito 
# ERROR:  could not open file "base/7517593/12281394": Read-only file system

SELECT count(*) from cnefe2010.subdistrito 
# ERROR:  could not open file "base/7517593/12281394": Read-only file system

SELECT count(*) from cnefe2010.setor 
# 312mil  312244

SELECT count(*) from cnefe2010.quadra  
# 2.1 milhoes  2145264

SELECT count(*) from cnefe2010.face 
# 7.4 milhoes  7404657

SELECT count(*) from cnefe2010.endereco 
# 11.3 milhoes  11330041

SELECT count(*), count(num_cep) from cnefe2010.endereco
# 11milhoes. 11330041

SELECT count(*) from cnefe2010.domicilio 
#11.3 milhoes  11330041




































