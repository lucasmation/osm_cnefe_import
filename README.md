osm_cnefe_import
================

Scripts to prepare CNEFE data, on street names and addresses in Brasil, to be imported/integrated into Opeen Street Map

Datasets and the project are described at this OSM Wiki: 

http://wiki.openstreetmap.org/wiki/CNEFE_data,_IBGE,_Brasil_import

###Preparing the machine 

Install Postgresql and PostGIS flowing this totorial: http://switch2osm.org/loading-osm-data/


```
mkdir ~/osm_cnefe_import
```



###Creating Database


```
sudo -u postgres createuser -s $USER
createdb osm_cnefe_import
psql -d osm_cnefe_import -c 'CREATE EXTENSION hstore; CREATE EXTENSION postgis;'
```





###Importing polygons of Setores Censitarios (enumeration districts):


Downloading the data:
```
mkdir ~/osm_cnefe_import/set_censitario
cd ~/osm_cnefe_import/set_censitario
wget -r -nd ftp://geoftp.ibge.gov.br/malhas_digitais/censo_2010/setores_censitarios/
unzip  '*.zip'
cp -p $(find . -name *SEE250GC_SIR.*) . 
rm -r */
```

Importing into Postgresql:
```
shp2pgsql -c -s 4674:4326 -I -W LATIN1 2010  public.shape_setor_censitario | psql -d osm_cnefe_import
```
obs: above, the switch -s changes spatial reference from SIRGAS2000(SRID=4674)  to WGS84 (SRID=4326)


###Importing CNEFE data:

Downloading the data:

```
mkdir ~/osm_cnefe_import/CNEFE
cd ~/osm_cnefe_import/CNEFE
wget -r -nd ftp://ftp.ibge.gov.br/Censos/Censo_Demografico_2010/Cadastro_Nacional_de_Enderecos_Fins_Estatisticos/
```
obs: downloading will take some time, there are 10904 files  totaling 926Mb 


###Importing OSM data:

Downloading the data:
```
mkdir ~/osm_cnefe_import/OSM_Brasil
cd ~/osm_cnefe_import/OSM_Brasil
wget -r -nd http://download.geofabrik.de/south-america/brazil-latest.osm.pbf
```
