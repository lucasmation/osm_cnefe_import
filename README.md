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
Here selection the createria to select roads, or other line types that define bocks could be refined. An alternative could be
``` sql
	line.highway NOT IN ('construction', 'footway', 'path', 'steps', 'track', 'cycleway', 'pedestrian', 'abandoned',
	'disused') AND 
	(line.service NOT IN ('parking_aisle', 'driveway') OR line.service is null) AND (line.access NOT IN ('no', 'private') or 	line.access is null) AND
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
N# of Street Segments|57.6mil|57.6mil|1751mil
ST_Union|475s|517s|?
ST_Dump(ST_Polygonize)|46s|42s|?
ST_Intersects()|611s|204s|?


All of OBS-Brazil is 30x larger than OSM-Sao Paulo


### Maching CNEFE and OSM city bocks
matching within cities... (as a PL/pgSQL loop, otherwise query takes too long or does not run)

The relevant tables are

CNEFE_blocks_Sao_Paulo
CNEFE_block_street_relation_Sao_Paulo

OSM_blocks_Sao_Paulo
OSM_block_street_relation_Sao_Paulo




   






