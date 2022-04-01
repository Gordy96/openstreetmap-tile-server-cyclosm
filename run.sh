#!/bin/bash

set -x

function waitDB() {
    i=1
    MAXCOUNT=60
    echo "Waiting for PostgreSQL to be running"
    while [ $i -le $MAXCOUNT ]
    do
        pg_isready -q && echo "PostgreSQL running" && break
        sleep 2
        i=$((i+1))
    done
    if [ $i -gt $MAXCOUNT ]; then
        echo "Timeout while waiting for PostgreSQL to be running"
        exit 2
    fi
}

function applyScripts() {
    for f in $(find /sql/*.sql -type f | sort); do
        echo "applying $f"
        psql -f $f
    done
}

if [ "$1" = "import" ]; then
    env
    waitDB

    # Download Luxembourg as sample if no data is provided
    if [ ! -f /data.osm.pbf ] && [ -z "$DOWNLOAD_PBF" ]; then
        echo "WARNING: No import file at /data.osm.pbf, so importing Luxembourg as example..."
        DOWNLOAD_PBF="https://download.geofabrik.de/europe/luxembourg-latest.osm.pbf"
        DOWNLOAD_POLY="https://download.geofabrik.de/europe/luxembourg.poly"
    fi

    if [ -n "$DOWNLOAD_PBF" ]; then
        echo "INFO: Download PBF file: $DOWNLOAD_PBF"
        wget "$WGET_ARGS" "$DOWNLOAD_PBF" -O /data.osm.pbf
        if [ -n "$DOWNLOAD_POLY" ]; then
            echo "INFO: Download PBF-POLY file: $DOWNLOAD_POLY"
            wget "$WGET_ARGS" "$DOWNLOAD_POLY" -O /data.poly
        fi
    fi

    # copy polygon file if available
    if [ -f /data.poly ]; then
        sudo -u renderer cp /data.poly /var/lib/mod_tile/data.poly
    fi

    # Import data
    osm2pgsql -d ${PGDATABASE:-gis} --create --slim -G --hstore --number-processes ${THREADS:-4} ${OSM2PGSQL_EXTRA_ARGS} /data.osm.pbf

    applyScripts

    # Register that data has changed for mod_tile caching purposes
    touch /var/lib/mod_tile/planet-import-complete

    exit 0
fi
if [ "$1" = "scripts" ]; then
    waitDB
    applyScripts
fi
if [ "$1" = "contours_convert" ]; then
    osmosis --read-xml /contours/osm/cnt.osm --write-pbf /contours/osm/cnt.osm.pbf
fi
if [ "$1" = "contours_dl" ]; then
    #cd /home/renderer/src/cyclosm-cartocss-style/dem
    cd /contours
    #eio clip -o srtm_30m.tif --bounds 44.311 22.031 52.413 40.303
    gdal_contour -i 10 -a height srtm.vrt srtm_30m_contours_10m
    # mono /Srtm2Osm/Srtm2Osm.exe \
    #     -cat 400 100 \
    #     -large \
    #     -bounds1 44.311 22.031 52.413 40.303 \
    #     -incrementid \
    #     -firstnodeid $(( 1 << 33 )) \
    #     -firstwayid $(( 1 << 33 )) \
    #     -maxwaynodes 256 \
    #     -o /contours/osm/cnt.osm
    # phyghtmap --polygon=/data.poly -j 2 -s 10 -0 --source=view3 --max-nodes-per-tile=0 --max-nodes-per-way=0 --pbf
    exit 0
fi
if [ "$1" = "contours_import" ]; then
    waitDB
    # Import contours
    psql -c "DROP DATABASE IF EXISTS contours;"
    createdb -E UTF8 -O renderer contours
    psql -d contours -c "CREATE EXTENSION postgis;"
    psql -d contours -c "CREATE EXTENSION hstore;"
    
    cd /contours/srtm_30m_contours_10m

    #shp2pgsql -p -I -g way -s 4326:900913 contour.shp contour > cnt1.sql
    #shp2pgsql -a -g way -s 4326:900913 contour.shp contour > cnt2.sql
    psql -d contours -f cnt1.sql
    psql -d contours -f cnt2.sql
    
    #osm2pgsql -d contours --slim --cache 5000 -x -k --number-processes ${THREADS:-4} --style /home/renderer/src/cyclosm-cartocss-style/dem/contours.style /contours/osm/cnt.osm.pbf
    psql -d contours -c "ALTER TABLE contour RENAME COLUMN way TO geometry;"
    psql -d contours -c "ALTER TABLE contour RENAME TO contours;"
    exit 0
fi
if [ "$1" = "run" ]; then
    # Clean /tmp
    rm -rf /tmp/*
    waitDB
    # Configure Apache CORS
    if [ "$ALLOW_CORS" == "enabled" ] || [ "$ALLOW_CORS" == "1" ]; then
        echo "export APACHE_ARGUMENTS='-D ALLOW_CORS'" >> /etc/apache2/envvars
    fi

    # Initialize Apache
    service apache2 restart

    # Configure renderd threads
    sed -i -E "s/num_threads=[0-9]+/num_threads=${THREADS:-4}/g" /usr/local/etc/renderd.conf

    # start cron job to trigger consecutive updates
    if [ "$UPDATES" = "enabled" ] || [ "$UPDATES" = "1" ]; then
      /etc/init.d/cron start
    fi

    # Run while handling docker stop's SIGTERM
    stop_handler() {
        kill -TERM "$child"
    }
    trap stop_handler SIGTERM

    sudo -u renderer renderd -f -c /usr/local/etc/renderd.conf &
    child=$!
    wait "$child"

    service postgresql stop

    exit 0
fi

echo "invalid command"
exit 1
