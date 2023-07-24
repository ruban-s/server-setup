#!/bin/bash

# Ensure user is root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root!" ; exit 1
fi

# Check if Homebrew is installed and install if necessary
which -s brew
if [[ $? != 0 ]]; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else
    brew update
fi

# List PHP versions
echo "Available PHP versions:"
brew search php | grep -E "^php(@[0-9.]+)?$"

# Ask for PHP version to install
read -p "Enter PHP version to install: " php_version
brew install php@${php_version}
echo 'export PATH="/usr/local/opt/php@${php_version}/bin:$PATH"' >> ~/.bash_profile
echo 'export PATH="/usr/local/opt/php@${php_version}/sbin:$PATH"' >> ~/.bash_profile
source ~/.bash_profile

# Ask for web server to install
read -p "Enter the web server to install (apache or nginx): " web_server
web_server=${web_server,,}  # Convert to lowercase
if [[ $web_server == 'apache' ]]; then
    brew install httpd
    sudo brew services start httpd
elif [[ $web_server == 'nginx' ]]; then
    brew install nginx
    sudo brew services start nginx
fi

# Install MariaDB
brew install mariadb
sudo brew services start mariadb

# Download and install phpMyAdmin
cd /var/www
curl -O https://www.phpmyadmin.net/downloads/phpMyAdmin-latest-all-languages.tar.gz
tar -xvzf phpMyAdmin-latest-all-languages.tar.gz
mv phpMyAdmin-* phpmyadmin
rm phpMyAdmin-latest-all-languages.tar.gz

# Generate random password
password=$(openssl rand -base64 16)
mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${password}'; FLUSH PRIVILEGES;"

echo "Installation completed!"
echo "MySQL root username: root"
echo "MySQL root password: ${password}"

