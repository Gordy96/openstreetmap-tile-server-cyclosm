FROM tile-base:latest

ENV PG_HOST=db
ENV PG_USER=renderer
ENV PG_PASSWORD=renderer
ENV PG_DBNAME=gis
ENV PG_PORT=5432

COPY simplified-land-polygons-complete-3857.zip /
COPY land-polygons-split-3857.zip /
COPY hs/colored /hgt
COPY hs/smooth.vrt /
COPY project.mml /

RUN apt -y install postgis
RUN pip3 install elevation

# Configure stylesheet
RUN mkdir -p /home/renderer/src \
 && cd /home/renderer/src \
 && rm -rf cyclosm-cartocss-style \
 && git clone https://github.com/Gordy96/cyclosm-cartocss-style.git \
 && git -C cyclosm-cartocss-style checkout 5c9eab44cbf0dc053d17c55f0ecca0cc72f066ca \
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
 && mv /hgt ./ \
 && gdalbuildvrt shade.vrt hgt/*.tif
 #&& cp /smooth.vrt shade.vrt

RUN cd /home/renderer/src/cyclosm-cartocss-style \
 && cp /project.mml ./ \
 && sed -i "s/host: \"{{pg_host}}\"/host: \"${PG_HOST}\"/g" project.mml \
 && sed -i "s/user: \"{{pg_user}}\"/user: \"${PG_USER}\"/g" project.mml \
 && sed -i "s/port: \"{{pg_port}}\"/port: \"${PG_PORT}\"/g" project.mml \
 && sed -i "s/password: \"{{pg_password}}\"/password: \"${PG_PASSWORD}\"/g" project.mml \
 && sed -i "s/dbname: \"{{pg_dbname}}\"/dbname: \"${PG_DBNAME}\"/g" project.mml \
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

# Start running
COPY run.sh /
ENTRYPOINT ["/run.sh"]
CMD []

EXPOSE 80
