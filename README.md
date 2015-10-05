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

However, each address in CNEFE contains a "city block code". Thus, it is possible to aggregate CNEFE into a dataset of city blocks, characterized by their surounding streets. With some SQL magic, OSM data can also be aggregated into a similar city block datasey with souringing streets for each block. Therefore, as long as street names are the same in the two datasets, OSM and CNEFE city blocks can be matched. 

The code at OMS_and_CNEFE_blocks_matching.sql does that




   






