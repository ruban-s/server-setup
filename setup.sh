#!/bin/bash

# Ensure user is root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root!" ; exit 1
fi

# Confirm OS is Ubuntu or Debian
os_name=$(lsb_release -is)
if [[ $os_name != "Ubuntu" ]] && [[ $os_name != "Debian" ]]; then
    echo "This script can only be run on Ubuntu or Debian!" ; exit 1
fi

# Update system and install PHP repository
apt-get update && apt-get upgrade -y
apt-get install software-properties-common -y
add-apt-repository ppa:ondrej/php -y
apt-get update

echo "Available PHP versions:"
apt-cache madison php | awk '{print $3}' | grep -Po '[0-9]\.[0-9]+' | sort -u

# Ask for PHP versions to install and sort to get the highest
read -p "Enter PHP versions to install (separated by comma): " php_versions
IFS=',' read -ra versions <<< "$php_versions"
IFS=$'\n' sorted_versions=($(sort -n <<<"${versions[*]}"))
unset IFS
highest_version=${sorted_versions[-1]}

# Install PHP versions and extensions
extensions=("bcmath" "xml" "fpm" "mysql" "zip" "intl" "ldap" "gd" "cli" "bz2" "curl" "mbstring" "pgsql" "opcache" "soap" "cgi" "imap" "apcu" "xsl")
for version in "${versions[@]}"; do
    apt-get install "php${version}" "php${version}-${extensions[@]}" -y
done

# Ask for web server to install and handle installation
read -p "Enter the web server to install (apache or nginx): " web_server
web_server=${web_server,,}  # Convert to lowercase
if [[ $web_server == 'apache' ]]; then
    apt-get install apache2 -y && apt-get remove nginx -y
elif [[ $web_server == 'nginx' ]]; then
    apt-get install nginx -y && apt-get remove apache2 -y
fi

# Install and configure MariaDB
apt-get install mariadb-server -y
mysql_secure_installation

# Install PHPMyAdmin and configure for NGINX if applicable
apt-get install phpmyadmin -y

if [[ $web_server == 'nginx' ]]; then
    cat > /etc/nginx/snippets/phpmyadmin.conf << EOF
location /phpmyadmin {
    root /usr/share/;
    index index.php index.html index.htm;
    location ~ ^/phpmyadmin/(.+\.php)$ {
        try_files \$uri =404;
        root /usr/share/;
        fastcgi_pass unix:/run/php/php${highest_version}-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include /etc/nginx/fastcgi_params;
    }

    location ~* ^/phpmyadmin/(.+\.(jpg|jpeg|gif|css|png|js|ico|html|xml|txt))$ {
        root /usr/share/;
    }
}
EOF
    systemctl reload nginx
fi

# Configure MySQL root with random password
password=$(openssl rand -base64 16)
mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${password}'; FLUSH PRIVILEGES;"

echo "Installation completed!"
echo "MySQL root username: root"
echo "MySQL root password: ${password}"
