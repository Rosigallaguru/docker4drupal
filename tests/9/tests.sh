#!/usr/bin/env bash

set -e

if [[ -n "${DEBUG}" ]]; then
  set -x
fi

check_rq() {
  echo "Checking requirement: ${1} must be ${2}"
  drush rq --format=json | jq '.[] | select(.title=="'"${1}"'") | .value' | grep -q "${2}"
  echo "OK"
}

check_status() {
  echo "Checking status: ${1} must be ${2}"
  drush status --format=yaml | grep -q "${1}: ${2}"
  echo "OK"
}

DB_URL="${DB_DRIVER}://${DB_USER}:${DB_PASSWORD}@${DB_HOST}/${DB_NAME}"

make init -f /usr/local/bin/actions.mk

composer require -n \
  drupal/redis \
  drupal/purge \
  drupal/varnish_purge
#    does not support Drupal 9 yet
#composer require -n drupal/cache_tags

composer require -n \
  drupal/search_api \
  drupal/search_api_solr:~4

cd ./web

drush si -y --db-url="${DB_URL}"

# Test Drupal status and requirements
check_status "drush-version" "11.*"
check_status "root" "${APP_ROOT}/${DOCROOT_SUBDIR}"
check_status "site" "sites/default"
check_status "files" "sites/default/files"
check_status "temp" "/tmp"

check_rq "Database system" "MariaDB"
check_rq "Image toolkit" "gd"
check_rq "PHP OPcode caching" "Enabled"
check_rq "PHP" "${PHP_VERSION}"
check_rq "File system" "Writable"
check_rq "Configuration files" "Protected"

drush en -y \
  redis \
  purge \
  purge_queuer_coretags \
  purge_drush \
  varnish_purger \
  varnish_purge_tags
#  \
#  cache_tags

drush en -y \
  search_api \
  search_api_solr

# Enable redis
chmod 755 "${PWD}/sites/default/settings.php"
echo "include '${PWD}/sites/default/test.settings.php';" >>"${PWD}/sites/default/settings.php"
check_rq "Redis" "Connected"

check_rq "Trusted Host Settings" "Enabled"

# @todo enabled when drupal console will be installed.
# Import solr server
#drupal cis --file search_api.server.solr.yml --directory /var/www/html/web
#drush sapi-sl | grep -q enabled

# @TODO return varnish tests after purge module drush commands support drush 9

## Test varnish cache and purge
#cp varnish-purger.yml purger.yml
#
#drush ppadd varnish
#drush cr

## Workaround for varnish purger import https://www.drupal.org/node/2856221
#PURGER_ID=$(drush ppls --format=json | jq -r "keys[0]")
#
#sed -i "s/PLUGIN_ID/${PURGER_ID}/g" purger.yml
#mv purger.yml "varnish_purger.settings.${PURGER_ID}.yml"
#drupal cis --file "varnish_purger.settings.${PURGER_ID}.yml"
#
#drush -y config-set system.performance cache.page.max_age 43200
#
#curl -Is varnish:6081 | grep -q "X-Varnish-Cache: MISS"
#curl -Is varnish:6081 | grep -q "X-Varnish-Cache: HIT"
#
#drush cc render
#drush pqw
#
#curl -Is varnish:6081 | grep -q "X-Varnish-Cache: MISS"
#curl -Is varnish:6081 | grep -q "X-Varnish-Cache: HIT"
