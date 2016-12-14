#!/bin/bash

# Make the script exit early if any command fails
set -e

# Add PPAs
apt-get update

apt-get install -yq python-software-properties python-setuptools git

add-apt-repository -y ppa:chris-lea/node.js

apt-get update

cp -rTv --remove-destination /vagrant/configs /

# Stop all the services if they are already running
service otm-unicorn stop || true
service tiler stop || true
service ecoservice stop || true
service celeryd stop || true

# nodejs & redis - needed for django and tiler
apt-get install -yq nodejs redis-server

# Django + GeoDjango
apt-get install -yq gettext libgeos-dev libproj-dev libgdal1-dev build-essential python-pip python-dev

# DB
apt-get install -yq postgresql postgresql-server-dev-9.3 postgresql-contrib postgresql-9.3-postgis-2.1
service postgresql start

# Don't do any DB stuff if it already exists
if ! sudo -u postgres psql otm -c ''; then
    # Need to drop and recreate cluster to get UTF8 DB encoding
    sudo -u postgres pg_dropcluster --stop 9.3 main
    sudo -u postgres pg_createcluster --start 9.3 main  --locale="en_US.UTF-8"
    sudo -u postgres psql -c "CREATE USER otm SUPERUSER PASSWORD 'otm'"
    sudo -u postgres psql template1 -c "CREATE EXTENSION IF NOT EXISTS hstore"
    sudo -u postgres psql template1 -c "CREATE EXTENSION IF NOT EXISTS fuzzystrmatch"
    sudo -u postgres psql -c "CREATE DATABASE otm OWNER otm"
    sudo -u postgres psql otm -c "CREATE EXTENSION IF NOT EXISTS postgis"
fi

# Pillow
apt-get install -yq libfreetype6-dev

# OTM2 (UI testing)
apt-get install -yq xvfb firefox
# OTM2 (JS testing)
npm install -g testem

cd /usr/local/otm/app
pip install -r requirements.txt
pip install -r dev-requirements.txt
pip install -r test-requirements.txt

# Make local directories
mkdir -p /usr/local/otm/static || true
mkdir -p /usr/local/otm/media || true
chown vagrant:vagrant /usr/local/otm/static
chown vagrant:vagrant /usr/local/otm/media
chmod 777 /usr/local/otm/media

# Fetch newer version of nodejs, to use for bundling assets
NODE_VERSION_FOR_WEBPACK=0.12.15
sudo npm install -g nave
nave install $NODE_VERSION_FOR_WEBPACK

# Bundle JS and CSS
nave use $NODE_VERSION_FOR_WEBPACK npm install
python opentreemap/manage.py collectstatic_js_reverse
nave use $NODE_VERSION_FOR_WEBPACK npm run build
nave use $NODE_VERSION_FOR_WEBPACK python opentreemap/manage.py collectstatic --noinput

# Run Django migrations
python opentreemap/manage.py migrate
python opentreemap/manage.py create_system_user

# ecobenefits - init script
apt-get install -yq libgeos-dev mercurial
cd /usr/local/ecoservice
if ! go version; then
    wget -q "https://storage.googleapis.com/golang/go1.6.3.linux-amd64.tar.gz" -O /tmp/go.tar.gz
    tar -C /usr/local -xzf /tmp/go.tar.gz
    sudo ln -s /usr/local/go/bin/go /usr/local/bin/go
fi
if ! which godep; then
    export GOPATH="/home/vagrant/.gopath"
    mkdir $GOPATH || true
    go get github.com/tools/godep
    sudo ln -sf $GOPATH/bin/godep /usr/local/bin/godep
fi
export GOPATH="/usr/local/ecoservice"
make build

# tiler
apt-get install -yq libsigc++-2.0-dev libmapnik-dev mapnik-utils
cd /usr/local/tiler
npm install

# nginx
apt-get install -yq nginx
rm /etc/nginx/sites-enabled/default || true
ln -sf /etc/nginx/sites-available/otm.conf /etc/nginx/sites-enabled/otm

initctl reload-configuration

service otm-unicorn start
service tiler start
service ecoservice start
service celeryd start
service nginx restart
