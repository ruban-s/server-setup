# Multi-PHP Installation Script

This script automatically installs multiple versions of PHP and a chosen web server (Apache or NGINX) on Ubuntu or Debian systems. The script also installs and configures MariaDB, PHPMyAdmin, and sets up MySQL root with a random password.

## Requirements

* Ubuntu, Debian, Mac operating system.
* Root user access.

## How to use

1. Clone the repository:

    ```bash
    git clone https://github.com/ruban-s/server-setup.git
    ```

2. Navigate to the directory:

    ```bash
    cd server-setup
    ```

3. Give executable permissions to the script:

    ```bash
    chmod -R 777 setup.sh
    ```

4. Run the script as root:

    ```bash
    sudo ./setup.sh
    ```

    ### or Mac

    ```bash
    sudo ./setup-mac.sh
    ```
   

6. The script will prompt you to enter the PHP versions you want to install. Enter the versions, separated by a comma, for example:

    ```bash
    Enter PHP versions to install (separated by comma): 7.4,8.0
    ```

7. Then the script will ask you which web server to install: `apache` or `nginx`. Enter your choice:

    ```bash
    Enter the web server to install (apache or nginx): nginx
    ```

8. The script will then proceed to install the chosen PHP versions, the web server, MariaDB, and PHPMyAdmin. It will also set up MySQL root with a random password.

## Note

* Make sure to back up your configurations before running the script, as it may modify existing configurations.
* This is a basic setup and the actual configuration may depend on your specific needs and environment. Always check the official PHP and MariaDB documentation for the latest configuration information.
* This script should be run on a non-production environment first to ensure that it works as expected.

## Support

If you have any questions or run into any issues, please open an issue in this repository.
