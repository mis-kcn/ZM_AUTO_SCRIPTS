#!/bin/bash

# Exit on error
set -e

if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

DOMAIN_NAME=""
SSL_CONF="/etc/apache2/sites-available/000-default-le-ssl.conf"
ZM_CONF="/etc/apache2/conf-enabled/zoneminder.conf"
ADMIN_PASSWORD=""

# Ask for domain
while true; do
    read -p "Enter domain name: " DOMAIN_NAME
    if [ -n "$DOMAIN_NAME"]; then
        break
    fi
done

# Ask for admin password
while true; do
    read -p "Enter ZM admin password: " ADMIN_PASSWORD
    if [ -n "$ADMIN_PASSWORD" ]; then
        break
    fi
done

echo -e "\e[1;42m Update and Upgrading System \e[0m"

# Update and upgrade system
sudo apt-get update && sudo apt upgrade -y

echo -e "\e[1;42m Installing software-properties-common \e[0m"

# Install necessary packages
sudo apt install -y software-properties-common

echo -e "\e[1;42m Adding ZM PPA \e[0m"

# Add PPA for ZoneMinder 1.36
sudo add-apt-repository -y ppa:iconnor/zoneminder-1.36

echo -e "\e[1;42m Updating System \e[0m"

# Update system
sudo apt update

echo -e "\e[1;42m Installing MariaDB \e[0m"

# Install MariaDB
apt-get install -y mariadb-server

echo -e "\e[1;42m Installing ZM... \e[0m"

# ZoneMinder installation
sudo apt install -y zoneminder

echo -e "\e[1;42m Setting up Apache2 \e[0m"

# Setup apache2 configurations
sudo a2enmod rewrite headers cgi
sudo a2enconf zoneminder

echo -e "\e[1;42m Restarting system services \e[0m"

# Restart services
sudo systemctl restart apache2
sudo systemctl enable zoneminder
sudo systemctl start zoneminder

echo -e "\e[1;42m Updating System \e[0m"

sudo apt update

HEADERS_CONF="/tmp/multiline_insert.txt"

cat <<'EOF' > "$HEADERS_CONF"
Header always set Access-Control-Allow-Origin "*"
Header always set Access-Control-Request-Methods "Authorization"
Header always set Access-Control-Methods "OPTIONS, GET, POST, DELETE, PUT"
Header always set Access-Control-Allow-Methods "OPTIONS, GET, POST, DELETE, PUT"
Header always set Access-Control-Allow-Headers "X-Requested-With, Content-Type, Authorization, Origin, Accept, client-security-token"
Header always set Access-Control-Expose-Headers "Content-Security-Policy, Location"
Header always set Access-Control-Max-Age "1000"
EOF

# Check if ZoneMinder configuration file exists
echo -e "\e[1;42m Fixing CORS in ZM Config... \e[0m"

if [ ! -f "$ZM_CONF" ]; then
    echo "Error: ZoneMinder configuration file not found"
    exit 1
fi

# Backup ZoneMinder configuration file
cp "$ZM_CONF" "$ZM_CONF.bak"

# Insert headers configuration into ZoneMinder configuration file
sed -i "6r $HEADERS_CONF" "$ZM_CONF"
sed -i "24r $HEADERS_CONF" "$ZM_CONF"
sed -i "39r $HEADERS_CONF" "$ZM_CONF"
sed -i "56r $HEADERS_CONF" "$ZM_CONF"
sed -i "70r $HEADERS_CONF" "$ZM_CONF"
sed -i "85r $HEADERS_CONF" "$ZM_CONF"

# Run config test
apachectl configtest

# Set ZoneMinder admin password
echo -e "\e[1;42m Setting ZM admin password \e[0m"
mysql -u root -p="" -e "USE zm; update Users set Password=PASSWORD('$ADMIN_PASSWORD') where Username='admin';"

# Enable ZoneMinder authentication
echo -e "\e[1;42m Enabling ZM authentication \e[0m"
mysql -u root -p="" -e "USE zm; UPDATE Config set Value=1 where Name='ZM_OPT_USE_AUTH';"

# Disable ZoneMinder relay authentication
echo -e "\e[1;42m Disabling ZM relay authentication \e[0m"
mysql -u root -p="" -e 'USE zm; UPDATE Config set Value="none" where Name="ZM_AUTH_RELAY";'

# Disable ZoneMinder privacy mask
echo -e "\e[1;42m Disabling ZM privacy mask \e[0m"
mysql -u root -p="" -e 'USE zm; UPDATE Config set Value=0 where Name="ZM_SHOW_PRIVACY";'

yes | zmupdate.pl


### - SSL Configuration - ###

# Install certbot
echo -e "\e[1;42m Installing certbot \e[0m"
sudo apt install -y certbot python3-certbot-apache

echo -e "\e[1;42m Allowing Apache through the Firewall \e[0m"

sudo ufw allow 'Apache Full'

echo -e "\e[1;42m Requesting for Certificate... \e[0m"

sudo certbot --apache --non-interactive --agree-tos -m kcniverba@myinternetsupport.com -d "$DOMAIN_NAME"

# Check if SSL configuration file exists
echo -e "\e[1;42m Fixing CORS in SSL Apache conf... \e[0m"

if [ ! -f "$SSL_CONF" ]; then
    echo "Error: SSL configuration file not found"
    exit 1
fi

# Backup SSL configuration file
cp "$SSL_CONF" "$SSL_CONF.bak"

# Insert headers configuration into SSL configuration file
sed -i "34r $HEADERS_CONF" "$SSL_CONF"

# Run config test
apachectl configtest
