-- Flowing the suggestions at http://stackoverflow.com/questions/32907481/optimize-large-st-intersect-query-match-1-8m-osm-streets-to-317k-polygons 
-- I tryed different aprochages to matching the 1.8 million strets in OSM of Brazil to the 317k Enumeration districts. 
-- (I haven`t actually run the queries yet)




----------------------
-- A, B, C  . Creating spatial Indexes and CLUSTERING ON THEM. Not matching on muncipal codes
 -- A = criating buffer as subquery . B = pre-creating buffer in separate query . C = using ST_DWithin


-- A) subquery to create buffer
EXPLAIN
CREATE TABLE OSM_Streets_by_SetorCensitario AS
SELECT osm_id, cd_geocodi as cod_setor
FROM OSM_Streets
INNER JOIN
        (SELECT *, ST_Buffer(geom,0.005) as geom_buffed
        FROM setor_censitarioL) AS foo
ON ST_Intersects(way,geom_buffed)
 
"Nested Loop  (cost=0.00..284628404933.70 rows=185124060285 width=24)"
"  Join Filter: st_intersects(osm_streets.way, st_buffer(setor_censitariol.geom, 0.005::double precision))"
"  ->  Seq Scan on osm_streets  (cost=0.00..75902.88 rows=1753988 width=190)"
"  ->  Materialize  (cost=0.00..58671.51 rows=316634 width=2145)"
"        ->  Seq Scan on setor_censitariol  (cost=0.00..57088.34 rows=316634 width=2145)"
 

--B) pre compiling the buffer and running the main query
drop table setor_censitarioL2
CREATE TABLE setor_censitarioL2 AS
SELECT 	*, substring(cd_geocodi,1,7) AS cod_mun , 
	ST_Buffer(geom,0.005) as geom_buffed
FROM setor_censitarioL;
CREATE INDEX setor_censitarioL2_index2 ON setor_censitarioL2 USING gist  (cod_mun);  

 
EXPLAIN
CREATE TABLE OSM_Streets_by_SetorCensitario AS
SELECT osm_id, cd_geocodi as cod_setor
FROM OSM_Streets
INNER JOIN  setor_censitarioL2
ON ST_Intersects(way,geom_buffed);

"Nested Loop  (cost=0.41..15401715.81 rows=597184609 width=24)"
"  ->  Seq Scan on setor_censitariol2  (cost=0.00..119821.74 rows=316574 width=1921)"
"  ->  Index Scan using osm_streets_index on osm_streets  (cost=0.41..47.69 rows=58 width=190)"
"        Index Cond: (way && setor_censitariol2.geom_buffed)"
"        Filter: _st_intersects(way, setor_censitariol2.geom_buffed)"
 
 
--C) Matching with ST_DWithin
EXPLAIN
CREATE TABLE OSM_Streets_by_SetorCensitario AS
SELECT osm_id, cd_geocodi as cod_setor
FROM OSM_Streets
INNER JOIN  setor_censitarioL
ON ST_DWithin(way,geom,0.005);

"Nested Loop  (cost=0.41..15439215.66 rows=185124 width=24)"
"  ->  Seq Scan on setor_censitariol  (cost=0.00..57088.34 rows=316634 width=2145)"
"  ->  Index Scan using osm_streets_index on osm_streets  (cost=0.41..48.57 rows=1 width=190)"
"        Index Cond: (way && st_expand(setor_censitariol.geom, 0.005::double precision))"
"        Filter: ((setor_censitariol.geom && st_expand(way, 0.005::double precision)) AND _st_dwithin(way, setor_censitariol.geom, 0.005::double precision))"



-------------------------
-- D, E. The difference now is that I add indexes on cod_mun for both tables and use the cod_mun as a matching criteria. 
--        Note that the CLUSTER is still only on the index of the spatial index
--    D = pre-creating buffer in separate query . E = using ST_DWithin


-- i.e. I created the index for cod_mun on both tables
CREATE INDEX 	setor_censitarioL2_index  	ON setor_censitarioL2 USING gist  (geom);
CREATE INDEX 	setor_censitarioL2_index2 	ON setor_censitarioL2 USING gist  (cod_mun);  
CLUSTER 	setor_censitarioL2 	using setor_censitarioL2_index2; -- 75s


CREATE INDEX OSM_Streets_by_Mun_index  	ON OSM_Streets_by_Mun USING gist  (way);
CREATE INDEX OSM_Streets_by_Mun_index2 ON OSM_Streets_by_Mun USING gist  (cod_mun);
CLUSTER OSM_Streets_by_Mun using OSM_Streets_by_Mun_index;


--D) 

EXPLAIN
CREATE TABLE OSM_Streets_by_SetorCensitario AS
SELECT osm_id, cd_geocodi as cod_setor
FROM OSM_Streets_by_mun
INNER JOIN  setor_censitarioL2
ON 	OSM_Streets_by_mun.cod_mun=setor_censitarioL2.cod_mun AND
	ST_Intersects(way,geom_buffed);


"Nested Loop  (cost=0.41..531970.67 rows=2854485 width=24)"
"  ->  Seq Scan on setor_censitariol2  (cost=0.00..119821.74 rows=316574 width=1929)"
"  ->  Index Scan using osm_streets_by_mun_index3 on osm_streets_by_mun  (cost=0.41..1.29 rows=1 width=268)"
"        Index Cond: (((cod_mun)::text = setor_censitariol2.cod_mun) AND (way && setor_censitariol2.geom_buffed))"
"        Filter: _st_intersects(way, setor_censitariol2.geom_buffed)"



--E) Matching with municipal code and ST_DWithin

EXPLAIN
CREATE TABLE OSM_Streets_by_SetorCensitario AS
SELECT osm_id, cd_geocodi as cod_setor
FROM OSM_Streets_by_mun
INNER JOIN  setor_censitarioL2
ON 	OSM_Streets_by_mun.cod_mun=setor_censitarioL2.cod_mun AND
	ST_DWithin(way,geom,0.005);

"Nested Loop  (cost=0.41..534344.97 rows=744 width=24)"
"  ->  Seq Scan on setor_censitariol2  (cost=0.00..119821.74 rows=316574 width=2156)"
"  ->  Index Scan using osm_streets_by_mun_index3 on osm_streets_by_mun  (cost=0.41..1.30 rows=1 width=268)"
"        Index Cond: (((cod_mun)::text = setor_censitariol2.cod_mun) AND (way && st_expand(setor_censitariol2.geom, 0.005::double precision)))"
"        Filter: ((setor_censitariol2.geom && st_expand(way, 0.005::double precision)) AND _st_dwithin(way, setor_censitariol2.geom, 0.005::double precision))"



-------------------------
-- F, G  Now I create index base on both cod_mun and spatial variable. And cluster both datases on that index
--    F = pre-creating buffer in separate query . G = using ST_DWithin

CREATE INDEX 	setor_censitarioL2_index3 	ON setor_censitarioL2 USING gist  (cod_mun,geom);  --46s
CLUSTER 	setor_censitarioL2 	using setor_censitarioL2_index3; -- 131s


CREATE INDEX 	OSM_Streets_by_Mun_index3 	ON OSM_Streets_by_Mun USING gist  (cod_mun,way);
CLUSTER 	OSM_Streets_by_Mun using OSM_Streets_by_Mun_index3; -- 743



--F) 

EXPLAIN
CREATE TABLE OSM_Streets_by_SetorCensitario AS
SELECT osm_id, cd_geocodi as cod_setor
FROM OSM_Streets_by_mun
INNER JOIN  setor_censitarioL2
ON 	OSM_Streets_by_mun.cod_mun=setor_censitarioL2.cod_mun AND
	ST_Intersects(way,geom_buffed);


"Nested Loop  (cost=0.41..528928.67 rows=2854485 width=24)"
"  ->  Seq Scan on setor_censitariol2  (cost=0.00..119875.74 rows=316574 width=1929)"
"  ->  Index Scan using osm_streets_by_mun_index3 on osm_streets_by_mun  (cost=0.41..1.28 rows=1 width=268)"
"        Index Cond: (((cod_mun)::text = setor_censitariol2.cod_mun) AND (way && setor_censitariol2.geom_buffed))"
"        Filter: _st_intersects(way, setor_censitariol2.geom_buffed)"



--G) Matching with municipal code and ST_DWithin

EXPLAIN
CREATE TABLE OSM_Streets_by_SetorCensitario AS
SELECT osm_id, cd_geocodi as cod_setor
FROM OSM_Streets_by_mun
INNER JOIN  setor_censitarioL2
ON 	OSM_Streets_by_mun.cod_mun=setor_censitarioL2.cod_mun AND
	ST_DWithin(way,geom,0.005);

"Nested Loop  (cost=0.41..531302.97 rows=744 width=24)"
"  ->  Seq Scan on setor_censitariol2  (cost=0.00..119875.74 rows=316574 width=2156)"
"  ->  Index Scan using osm_streets_by_mun_index3 on osm_streets_by_mun  (cost=0.41..1.29 rows=1 width=268)"
"        Index Cond: (((cod_mun)::text = setor_censitariol2.cod_mun) AND (way && st_expand(setor_censitariol2.geom, 0.005::double precision)))"
"        Filter: ((setor_censitariol2.geom && st_expand(way, 0.005::double precision)) AND _st_dwithin(way, setor_censitariol2.geom, 0.005::double precision))"
