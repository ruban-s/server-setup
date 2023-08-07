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

# Check where to start based on flag files
if [ -f "/var/tmp/php_installation_complete" ]; then
    echo "Installation already completed."
    exit 0
elif [ -f "/var/tmp/php_web_server_installed" ]; then
    echo "Web server already installed. Proceeding to MariaDB installation..."
    goto_mariadb=true
elif [ -f "/var/tmp/php_versions_installed" ]; then
    echo "PHP versions already installed. Proceeding to web server installation..."
    goto_webserver=true
elif [ -f "/var/tmp/php_repository_added" ]; then
    echo "PHP repository already added. Proceeding to PHP versions installation..."
    goto_php_versions=true
fi

# Update system and install PHP repository
if [ ! "$goto_php_versions" ]; then
    apt-get update && apt-get upgrade -y
    apt-get install software-properties-common -y
    add-apt-repository ppa:ondrej/php -y
    apt-get update
    touch /var/tmp/php_repository_added
fi

# Available PHP versions
available_versions=$(apt-cache pkgnames | grep -Po '^php[0-9]\.[0-9]+$' | sort -Vu)
available_versions=${available_versions//php/} # Remove "php" prefix

# Ask for PHP versions to install
if [ ! "$goto_php_versions" ]; then
    read -p "Enter PHP versions to install (separated by comma): " php_versions
    IFS=',' read -ra versions <<< "$php_versions"
    for version in "${versions[@]}"; do
        if [[ ! " $available_versions " =~ " $version " ]]; then
            echo "Version $version is not available. Exiting..."
            exit 1
        fi
    done
    IFS=$'\n' sorted_versions=($(sort -V <<<"${versions[*]}"))
    unset IFS
    highest_version=${sorted_versions[-1]}

    # Install PHP versions and extensions
    extensions=("bcmath" "xml" "fpm" "mysql" "zip" "intl" "ldap" "gd" "cli" "bz2" "curl" "mbstring" "pgsql" "opcache" "soap" "cgi" "imap" "apcu" "xsl")
    for version in "${versions[@]}"; do
        apt-get install "php${version}" $(printf "php${version}-%s " "${extensions[@]}") -y || {
            echo "Failed to install PHP version $version. Exiting..."
            exit 1
        }
    done
    touch /var/tmp/php_versions_installed
fi

# Ask for web server to install and handle installation
if [ ! "$goto_webserver" ] && [ ! "$goto_php_versions" ]; then
    read -p "Enter the web server to install (apache or nginx): " web_server
    web_server=${web_server,,}  # Convert to lowercase
    if [[ $web_server == 'apache' ]]; then
        apt-get install apache2 -y && apt-get remove nginx -y
    elif [[ $web_server == 'nginx' ]]; then
        apt-get install nginx -y && apt-get remove apache2 -y
    fi
    touch /var/tmp/php_web_server_installed
fi

# Install and configure MariaDB
if [ ! "$goto_mariadb" ] && [ ! "$goto_webserver" ] && [ ! "$goto_php_versions" ]; then
    apt-get install mariadb-server -y
    mysql_secure_installation
    # Install PHPMyAdmin and configure for NGINX if applicable
    apt-get install phpmyadmin -y

    if [[ $web_server == 'apache' ]]; then
    cat > /etc/apache2/conf-available/phpmyadmin.conf << EOF
Alias /phpmyadmin /usr/share/phpmyadmin
<Directory /usr/share/phpmyadmin>
    Options FollowSymLinks
    DirectoryIndex index.php

    <IfModule mod_php5.c>
        <IfModule mod_mime.c>
            AddType application/x-httpd-php .php
        </IfModule>
        <FilesMatch ".+\.php$">
            SetHandler application/x-httpd-php
        </FilesMatch>

        php_value include_path .
        php_admin_value upload_tmp_dir /var/lib/phpmyadmin/tmp
        php_admin_value open_basedir /usr/share/phpmyadmin/:/etc/phpmyadmin/:/var/lib/phpmyadmin/:/usr/share/php/php-gettext/:/usr/share/php/php-php-gettext/:/usr/share/javascript/:/usr/share/php/tcpdf/:/usr/share/doc/phpmyadmin/:/usr/share/php/phpseclib/
        php_admin_value mbstring.func_overload 0
    </IfModule>
    <IfModule mod_php.c>
        <IfModule mod_mime.c>
            AddType application/x-httpd-php .php
        </IfModule>
        <FilesMatch ".+\.php$">
            SetHandler application/x-httpd-php
        </FilesMatch>

        php_value include_path .
        php_admin_value upload_tmp_dir /var/lib/phpmyadmin/tmp
        php_admin_value open_basedir /usr/share/phpmyadmin/:/etc/phpmyadmin/:/var/lib/phpmyadmin/:/usr/share/php/php-gettext/:/usr/share/php/php-php-gettext/:/usr/share/javascript/:/usr/share/php/tcpdf/:/usr/share/doc/phpmyadmin/:/usr/share/php/phpseclib/
        php_admin_value mbstring.func_overload 0
    </IfModule>
</Directory>

# Authorize for setup
<Directory /usr/share/phpmyadmin/setup>
    <IfModule mod_authn_core.c>
        <IfModule mod_authn_file.c>
            AuthType Basic
            AuthName "phpMyAdmin Setup"
            AuthUserFile /etc/phpmyadmin/htpasswd.setup
        </IfModule>
    </IfModule>
    Require valid-user
</Directory>

# Disallow web access to directories that don't need it
<Directory /usr/share/phpmyadmin/templates>
    Require all denied
</Directory>
<Directory /usr/share/phpmyadmin/libraries>
    Require all denied
</Directory>
EOF
    # Enable the phpMyAdmin configuration
    a2enconf phpmyadmin

    systemctl reload apache2

elif [[ $web_server == 'nginx' ]]; then
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

    # Include the PHPMyAdmin configuration in the default Nginx site configuration
     awk '/server \{/{c++;if(c==2){sub(/}/,"    include snippets/phpmyadmin.conf;\n}");c=0}}1' /etc/nginx/sites-available/default > temp && mv temp /etc/nginx/sites-available/default
    
    systemctl reload nginx
fi

# Configure MySQL root with random password
password=$(openssl rand -base64 16)
mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${password}'; FLUSH PRIVILEGES;"


     touch /var/tmp/php_installation_complete
fi

echo "Installation completed!"
echo "MySQL root username: root"
echo "MySQL root password: ${password}"
