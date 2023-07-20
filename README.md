# PHP Server Setup Script

This repository contains a Bash script for setting up a PHP development environment on Ubuntu or Debian systems. It also includes MariaDB and options for either Apache or Nginx web servers.

## Prerequisites

- You need root access to your server.
- Your server must be running Ubuntu or Debian.

## Usage

Clone this repository to your server using the command:

```
https://github.com/ruban-s/server-setup.git
```
## Navigate to the repository and make the script executable:

```
cd server-setup
chmod +x setup.sh
```

## Run the script as root:

```
sudo ./setup.sh
```


The script will guide you through the installation process, prompting you to select which versions of PHP to install, and whether to install Apache or Nginx.

## What the Script Does

1. Checks if your server's OS is either Ubuntu or Debian.
2. Updates the system's package list and installs updates.
3. Installs the PHP software repository.
4. Installs the specified versions of PHP.
5. Installs a set of common PHP extensions.
6. Installs either Apache or Nginx based on your selection.
7. Installs MariaDB and runs the mysql_secure_installation script.
8. Installs PHPMyAdmin.
9. Changes the MySQL root user's authentication method to 'mysql_native_password'.
10. Generates a random password for the MySQL root user.
11. Displays the MySQL root username and the generated password at the end.

## Warning

This script is intended for use in a new environment and not in a old environment.
