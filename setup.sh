#!/bin/bash

# Check if the user is root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root!"
   exit 1
fi

# Check the operating system
os_name=$(lsb_release -is)

if [[ $os_name != "Ubuntu" ]] && [[ $os_name != "Debian" ]]; then
    echo "This script can only be run on Ubuntu or Debian!"
    exit 1
fi

# Update the system
echo "Updating system..."
apt-get update && apt-get upgrade -y

# Install the PHP repository
echo "Installing PHP repository..."
apt-get install software-properties-common -y
add-apt-repository ppa:ondrej/php -y
apt-get update

# Ask for PHP versions to be installed
read -p "Enter PHP versions to install (separated by comma): " php_versions
IFS=',' read -ra versions <<< "$php_versions"

# Extensions to be installed
extensions=("bcmath" "xml" "fpm" "mysql" "zip" "intl" "ldap" "gd" "cli" "bz2" "curl" "mbstring" "pgsql" "opcache" "soap" "cgi" "imap" "apcu" "xsl")

for version in "${versions[@]}"; do
    echo "Installing PHP ${version}..."
    apt-get install "php${version}" -y

    # Install the extensions
    for extension in "${extensions[@]}"; do
        echo "Installing PHP ${version} ${extension} extension..."
        apt-get install "php${version}-${extension}" -y
    done
done

# Ask for web server to install
read -p "Enter the web server to install (apache or nginx): " web_server
web_server=${web_server,,}  # Convert to lowercase

if [[ $web_server == 'apache' ]]; then
    echo "Installing Apache..."
    apt-get install apache2 -y
    echo "Removing Nginx if installed..."
    apt-get remove nginx -y
elif [[ $web_server == 'nginx' ]]; then
    echo "Installing Nginx..."
    apt-get install nginx -y
    echo "Removing Apache if installed..."
    apt-get remove apache2 -y
fi

# Install MariaDB and auto-configure
echo "Installing MariaDB..."
apt-get install mariadb-server -y
mysql_secure_installation

# Install PHPMyAdmin
echo "Installing PHPMyAdmin..."
apt-get install phpmyadmin -y

# Generate random password
password=$(openssl rand -base64 16)
echo "Setting up MySQL root with native password auth and new password: ${password}"

# Configure MySQL root with native password and new password
mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${password}'; FLUSH PRIVILEGES;"

echo "Installation completed!"
echo "MySQL root username: root"
echo "MySQL root password: ${password}"
