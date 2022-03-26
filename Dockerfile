FROM tile-base:latest

RUN apt-get install -y --no-install-recommends \
 gdal-bin \
 python-gdal \
 geotiff-bin \
 python3-setuptools \
 python3-matplotlib \
 python3-bs4 \
 python3-numpy \
 python3-gdal \
 python3-pip

RUN pip3 install lxml

RUN wget http://katze.tfiu.de/projects/phyghtmap/phyghtmap_2.23-1_all.deb -O phyghtmap.deb \
 && dpkg -i phyghtmap*.deb \
 && apt-get --fix-broken install

COPY simplified-land-polygons-complete-3857.zip /
COPY land-polygons-split-3857.zip /
COPY hs/colored /hgt
COPY hs/smooth.vrt /
# Configure stylesheet
RUN mkdir -p /home/renderer/src \
 && cd /home/renderer/src \
 && rm -rf cyclosm-cartocss-style \
 && git clone https://github.com/Gordy96/cyclosm-cartocss-style.git \
 && git -C cyclosm-cartocss-style checkout a6ee442165d0f4c10f64a69a5db664baa7e97cf2 \
 && cd cyclosm-cartocss-style \
 && rm -rf .git \
 && mkdir data \
 && cd data \
 && mv /simplified-land-polygons-complete-3857.zip ./ \
 && mv /land-polygons-split-3857.zip ./ \
 && unzip simplified-land-polygons-complete-3857.zip \
 && unzip land-polygons-split-3857.zip \
 && rm /home/renderer/src/cyclosm-cartocss-style/data/*.zip \
 && cd .. \
 && cd dem \
 && cp -R /hgt ./ \
 && gdalbuildvrt full.vrt hgt/*.tif \
 && cp /smooth.vrt shade.vrt \
 && cd .. \
 && sed -i 's/dbname: "osm"/dbname: "gis"/g' project.mml \
 && sed -i 's,http://osmdata.openstreetmap.de/download/simplified-land-polygons-complete-3857.zip,data/simplified-land-polygons-complete-3857/simplified_land_polygons.shp,g' project.mml \
 && sed -i 's,http://osmdata.openstreetmap.de/download/land-polygons-split-3857.zip,data/land-polygons-split-3857/land_polygons.shp,g' project.mml \
 && carto project.mml > mapnik.xml

# Configure renderd
RUN sed -i 's/renderaccount/renderer/g' /usr/local/etc/renderd.conf \
 && sed -i 's/\/truetype//g' /usr/local/etc/renderd.conf \
 && sed -i 's/hot/tile/g' /usr/local/etc/renderd.conf \
 && sed -i 's/openstreetmap-carto/cyclosm-cartocss-style/g' /usr/local/etc/renderd.conf

# Configure Apache
RUN mkdir -p /var/lib/mod_tile \
 && chown renderer /var/lib/mod_tile \
 && mkdir -p /var/run/renderd \
 && chown renderer /var/run/renderd \
 && echo "LoadModule tile_module /usr/lib/apache2/modules/mod_tile.so" >> /etc/apache2/conf-available/mod_tile.conf \
 && echo "LoadModule headers_module /usr/lib/apache2/modules/mod_headers.so" >> /etc/apache2/conf-available/mod_headers.conf \
 && a2enconf mod_tile && a2enconf mod_headers
COPY apache.conf /etc/apache2/sites-available/000-default.conf
COPY security.conf /etc/apache2/conf-enabled/security.conf
RUN rm -rf /var/www/html/index.html
RUN ln -sf /dev/stdout /var/log/apache2/access.log \
 && ln -sf /dev/stderr /var/log/apache2/error.log

# Configure PosgtreSQL
COPY postgresql.custom.conf.tmpl /etc/postgresql/12/main/
RUN chown -R postgres:postgres /var/lib/postgresql \
 && chown postgres:postgres /etc/postgresql/12/main/postgresql.custom.conf.tmpl \
 && echo "host all all 0.0.0.0/0 md5" >> /etc/postgresql/12/main/pg_hba.conf \
 && echo "host all all ::/0 md5" >> /etc/postgresql/12/main/pg_hba.conf

# Copy update scripts
COPY openstreetmap-tiles-update-expire /usr/bin/
RUN chmod +x /usr/bin/openstreetmap-tiles-update-expire \
 && mkdir -p /var/log/tiles \
 && chmod a+rw /var/log/tiles \
 && ln -s /home/renderer/src/mod_tile/osmosis-db_replag /usr/bin/osmosis-db_replag \
 && echo "*  *    * * *   renderer    openstreetmap-tiles-update-expire\n" >> /etc/crontab

# Install trim_osc.py helper script
RUN mkdir -p /home/renderer/src \
 && cd /home/renderer/src \
 && git clone https://github.com/zverik/regional \
 && cd regional \
 && git checkout 889d630a1e1a1bacabdd1dad6e17b49e7d58cd4b \
 && rm -rf .git \
 && chmod u+x /home/renderer/src/regional/trim_osc.py

RUN cd / \
 && apt install -y --no-install-recommends gnupg ca-certificates \
 && apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 3FA7E0328081BFF6A14DA29AA6A19B38D3D831EF \
 && echo "deb https://download.mono-project.com/repo/ubuntu stable-bionic main" | tee /etc/apt/sources.list.d/mono-official-stable.list \
 && apt update \
 && apt install -y mono-complete

RUN wget https://github.com/mibe/Srtm2Osm/releases/download/v1.14/Srtm2Osm-1.14.11.0.zip -O srtm2osm.zip \
 && unzip srtm2osm.zip \
 && rm srtm2osm.zip

# Start running
COPY run.sh /
ENTRYPOINT ["/run.sh"]
CMD []

EXPOSE 80 5432
