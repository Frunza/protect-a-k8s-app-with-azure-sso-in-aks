#!/bin/sh

# Exit immediately if a simple command exits with a nonzero exit value
set -e

echo "Updating license key in terraform-k8s/hub1.tf"
sed -i "s#_INSTANT3DHUB_LICENSE_KEY_#${INSTANT3DHUB_LICENSE_KEY}#" ./terraform-k8s/hub1.tf
echo "Replacement of INSTANT3DHUB_LICENSE_KEY done"

echo "Updating placeholders OAUTH2 placeholders in terraform-k8s/sso-inrastructure.tf"
sed -i "s#_OAUTH2_CLIENT_ID_#${OAUTH2_CLIENT_ID}#" ./terraform-k8s/sso-inrastructure.tf
sed -i "s#_OAUTH2_CLIENT_SECRET_#${OAUTH2_CLIENT_SECRET}#" ./terraform-k8s/sso-inrastructure.tf
sed -i "s#_OAUTH2_TENANT_ID_#${ARM_TENANT_ID}#" ./terraform-k8s/sso-inrastructure.tf
sed -i "s#_OAUTH2_PROXY_COOKIE_SECRET_#${OAUTH2_PROXY_COOKIE_SECRET}#" ./terraform-k8s/sso-inrastructure.tf
echo "Replacement of OAUTH2 placeholders done"