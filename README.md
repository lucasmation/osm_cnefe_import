osm_cnefe_import
================

This project aims to mactch the national address cadaster from  2010 Census of Brazil (CNEFE) to Opeen Street Map and evaluate the possibility of an import. 

Objectives:
1) Finding Street names for unanmed streets in OSM-Brazil
2)  Matching named Street Segments in OSM-Brazi to the corresponding Street Segments in CNEFE to add the adress informatoin, present in CNEFE. 

Matching theses data is not trivial, requiring serveral normalizations, spatial transformations, matches, etc. 

This requires setting up a Linux machine with PostGIS (I used Ubuntu 12.04, with PostgreSQL 9.3 and PostGis 2.1). 

The file import_data.md describes how to import the data main datasets.  

Bellow we describe the dataest and how to transform them for objectives 1 and 2. 


## Data description

### CNEFE data


### OSM data

Datasets and the project are described at this OSM Wiki: 

http://wiki.openstreetmap.org/wiki/CNEFE_data,_IBGE,_Brasil_import



## 1) Finding Street names for unanmed streets in OSM-Brazil

to be done

## 2) Matching named street segments in OSM and CNEFE

This is a difficult problem because CNEFE does not contain geometric features of roads (or city blocks). The most spatially precise geometries that can be attributed to CNEFE are the Enumeration Districts (setores censitarios) areas which can comprize of about 8 blocks). 

However, each address in CNEFE contains a "city block code". Thus, it is possible to aggregate CNEFE into a dataset of city blocks, caracterized by their surounding streets. OSM data can also be aggregated into a similar city block datasey with souringing streets for each block. Therefore, as long as street names are the same in the two datasets, OSM and CNEFE city blocks can be matched. The code bellow does that

### CNEFE city blocks

still waitting for CNEFE import code. In the end will generate tables

CNEFE_blocks_Sao_Paulo
CNEFE_block_street_relation_Sao_Paulo

### OSM city blocks

To create city blocks from OSM we use the following algorithm, inspired by [this post](http://gis.stackexchange.com/questions/80498/how-to-transform-a-set-of-street-segments-into-city-blocks-with-postgis2):

1) select only streets in OSM
``` sql 
CREATE TABLE OSM_streets AS
SELECT * 
FROM planet_osm_line
WHERE
    (highway='living_street' or highway='motorway' or highway='primary' or highway='proposed' or highway='raceway' or 
    highway='residential' or highway='road' or highway='secondary' or highway='tertiary' or 
    highway='track' or 
    highway='trunk' or highway='unclassified' or route='road')
CREATE INDEX OSM_streets_index ON OSM_streets USING gist  (way);

``` 
Here selection the createria to select roads, or other line types that define bocks could be refined. An alternative could be
``` sql
	line.highway NOT IN ('construction', 'footway', 'path', 'steps', 'track', 'cycleway', 'pedestrian', 'abandoned',
	'disused') AND 
	(line.service NOT IN ('parking_aisle', 'driveway') OR line.service is null) AND (line.access NOT IN ('no', 'private') or 	line.access is null) AND
``` 
Let me know if you have a more precise way to identify streets. 

2) match OSM_streets to the IBGE state and municipality layer
``` sql
CREATE TABLE OSM_Streets_by_Mun AS
SELECT cod_uf, cod_mun, OSM_Streets.*
FROM OSM_Streets, UFs_Brasil, municipios_Brasil
WHERE ST_Intersects(way,UFs_Brasil.geom) AND ST_Intersects(way,municipios_Brasil.geom)
CREATE INDEX OSM_Streets_by_Mun_index ON OSM_Streets_by_Mun USING gist  (way);
``` 

This is important to reduce the dimensionality of subsequent queries, constructing `blocks` only within municipality. OBS:Minor problem: This will lead to problems with blocks that cross municipall borders, which can occur in conurbated municipalities 


3) Create OSM blocks for each municipality

3a) Union all street segments into a coommon multiline geom (ST_Union() ) in each municipality
``` sql
CREATE TABLE OSM_streets_mergedlines AS
SELECT cod_mun,ST_Union(way) as geom 
FROM OSM_streets_by_Mun
GROUP BY cod_mun;
CREATE INDEX OSM_streets_mergedlines_index ON OSM_streets_mergedlines USING gist  (geom);
```
OBS: This generates a tale with 5538 municipalities. In the 2010 census municipal division there were 5564 municipalities. This 26 municipalities have no OSM data. 

3b)  extract all polygons formed from the unionioned streets using ST_Poligonize(). Theese are the city blocks. Notice it is necessary to Split multipoligon geom generated into a table with one poligon per line. 

``` sql
CREATE TABLE temp_OSM_blocks AS
SELECT cod_mun, (blocks).path[1] AS path , (blocks).geom AS geom , ST_Buffer((blocks).geom,-0.0005) AS geom2
FROM (SELECT cod_mun, ST_Dump(ST_Polygonize(geom)) AS blocks
      FROM OSM_streets_mergedlines
      GROUP BY cod_mun) AS foo;
CREATE INDEX temp_OSM_blocks_index ON temp_OSM_blocks USING gist(geom);
```
 
4) Bring the OSM city names to OSM Blocks

Find the intersection of created polygons with the original street dataset to recover the names of the streets that carachterize each city block.  

``` sql
drop table OSM_block_street_relation
CREATE TABLE OSM_block_street_relation AS
SELECT 	OSM_streets_by_mun.*, 
	temp_OSM_blocks.path,temp_OSM_blocks.geom, temp_OSM_blocks.geom2
FROM temp_OSM_blocks, OSM_streets_by_mun
WHERE 	temp_OSM_blocks.cod_mun = OSM_streets_by_mun.cod_mun AND 
	ST_Intersects(temp_OSM_blocks.geom, OSM_streets_by_mun.way) AND
	GeometryType(ST_Multi(ST_Intersection(temp_OSM_blocks.geom, OSM_streets_by_mun.way)))='MULTILINESTRING';
CREATE INDEX OSM_block_street_relation_index ON OSM_block_street_relation USING gist(geom);
```

5) Create OSM_Block with streetname array

``` sql
CREATE TABLE OSM_blocks
SELECT cod_mun, path, geom, geom2, 
	count(x) AS No_seg
	count(name) AS No_names
	count(distinct name) AS No_unique_names
	array_agg(osm_id ORDER BY name) AS osm_name_array
	array_agg(name ORDER BY name) AS osm_name_array;
CREATE INDEX OSM_blocks_index ON OSM_blocks USING gist(geom);
```


### OSM city blocks Sao Paulo

I previously prototyped the code with Sao Paulo data

1) select only streets in OSM and a certain municipality (in this case Sao Paulo)

``` sql 
CREATE TABLE OSM_streets_Sao_Paulo AS
select line.* 
 from planet_osm_line as line, planet_osm_polygon as poly
 where  (poly.admin_level='8' AND poly.name='São Paulo') AND 
	(line.highway='living_street' or line.highway='motorway' or line.highway='primary' or line.highway='proposed' or 		line.highway='raceway' or 
	line.highway='residential' or line.highway='road' or line.highway='secondary' or line.highway='tertiary' or 
	line.highway='track' or 
	line.highway='trunk' or line.highway='unclassified' or line.route='road') AND
        ST_Contains(poly.way,line.way)
``` 


2) Union all street segments into a coommon multiline geom (ST_Union() )

``` sql
create table OSM_streets_Sao_Paulo_mergedlines as
SELECT ST_Union(way) as geom FROM OSM_streets_Sao_Paulo;
``` 

3) extract all polygons formed from the unionioned streets using ST_Poligonize(). Theese are the city blocks. Notice it is necessary to Split multipoligon geom generated into a table with one poligon per line. 

``` sql
CREATE TABLE OSM_blocks_Sao_Paulo AS
select (blocks).path[1], (blocks).geom from
(select ST_Dump(ST_Polygonize(geom)) as blocks from OSM_streets_Sao_Paulo_mergedlines) as foo;
```

3b) (optional) For better visual rendering, substract (ST_Clip) the streets width from the city bock polygons. Preferably use street widths proportional to street type. 

``` sql
ALTER TABLE OSM_blocks_Sao_Paulo
ADD geom_space2 geometry;
UPDATE OSM_blocks_Sao_Paulo
SET geom_space2=ST_Buffer(geom,-0.0005);
```
the is a little bug above (I`m not able to see the gaps in Qgis)
To be uptated for a `buffer`  proportional to street width. 


4) Find the intersection of created polygons with the original street dataset to recover the names of the streets tha carachterize each city block.  

``` sql
create table OSM_block_street_relation_Sao_Paulo as
select OSM_blocks_Sao_Paulo.path, OSM_streets_Sao_Paulo.* ,
	ST_Intersects(OSM_blocks_Sao_Paulo.geom,OSM_streets_Sao_Paulo.way)  
from OSM_blocks_Sao_Paulo, OSM_streets_Sao_Paulo
where ST_Intersects(OSM_blocks_Sao_Paulo.geom, OSM_streets_Sao_Paulo.way)=true and 
      GeometryType(ST_Multi(ST_Intersection(OSM_blocks_Sao_Paulo.geom,OSM_streets_Sao_Paulo.way)))='MULTILINESTRING'
```



Now need to replicate 1-4 this for all of Brasil.


TABLE time to run steps above (1 to 4) in Sao Paulo and all of Brazil

query|Sao Paulo municipality|Sao Paulo min + spatial index |Brazil
---|---|---|---
N# of Street Segments|58k|58k|1751k
OSM_Streets_by_Mun |n.a.|n.a.|15min
ST_Union|8min|9min|167min
ST_Dump(ST_Polygonize)|1min|1min|4min
ST_Intersects()|10min|4min|59min
array_agg|a|a|a

All of OBS-Brazil is 30x larger than OSM-Sao Paulo


### Maching CNEFE and OSM city bocks
matching within cities... (as a PL/pgSQL loop, otherwise query takes too long or does not run)

The relevant tables are

CNEFE_blocks_Sao_Paulo
CNEFE_block_street_relation_Sao_Paulo

OSM_blocks_Sao_Paulo
OSM_block_street_relation_Sao_Paulo




   






