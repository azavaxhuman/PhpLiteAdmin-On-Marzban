#!/bin/bash

# Colors
colors=(
    "\033[38;2;255;105;180m"  # Foreground (#EA549F)
    "\033[38;2;255;20;147m"   # Red (#E92888)
    "\033[38;2;0;255;144m"    # Green (#4EC9B0)
    "\033[38;2;0;191;255m"    # Blue (#579BD5)
    "\033[38;2;102;204;255m"  # Bright Blue (#9CDCFE)
    "\033[38;2;242;242;242m"  # Bright White (#EAEAEA)
    "\033[38;2;0;255;255m"    # Cyan (#00B6D6)
    "\033[38;2;255;215;0m"    # Bright Yellow (#e9ad95)
    "\033[38;2;160;32;240m"   # Purple (#714896)
    "\033[38;2;255;36;99m"    # Bright Red (#EB2A88)
    "\033[38;2;0;255;100m"    # Bright Green (#1AD69C)
    "\033[38;2;0;255;255m"    # Bright Cyan (#2BC4E2)
    "\033[0m"                 # Reset
)
foreground=${colors[0]} red=${colors[1]} green=${colors[2]} blue=${colors[3]} brightBlue=${colors[4]} brightWhite=${colors[5]} cyan=${colors[6]} brightYellow=${colors[7]} purple=${colors[8]} brightRed=${colors[9]} brightGreen=${colors[10]} brightCyan=${colors[11]} reset=${colors[12]}

# Helper functions
print() { echo -e "${cyan}$1${reset}"; }
error() { echo -e "${red}✗ $1${reset}"; }
success() { echo -e "${green}✓ $1${reset}"; }
log() { echo -e "${blue}! $1${reset}"; }
input() { read -p "$(echo -e "${brightYellow}▶ $1${reset}")" "$2"; }
confirm() { read -p "$(echo -e "\n${purple}Press any key to continue...${reset}")"; }

# Function to check if input is a valid port number
is_valid_port() {
    [[ "$1" =~ ^[0-9]{1,5}$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}


check_success() {
    if [ $? -eq 0 ]; then
        success "$1"
    else
        error "$2"
        exit 1
    fi
}

make_directory() {
        local directory="$1"
mkdir -p "$directory" || { error "Failed to create directory $directory"; return 1; }
        success "Directory $directory created."
    }
# Function to check if the file path exists
is_valid_path() {
    [ -d "$1" ]
}

# SSL Generation Function
generate_ssl_certificates() {

    update_packages() {
            log "Updating packages..."
            apt update &> /dev/null && apt install -y socat &> /dev/null
            check_success "Package update completed." "Package update failed."
    }

    install_certbot() {

            log "Installing certbot..."
            apt install -y certbot &> /dev/null
            check_success "Certbot installation completed." "Certbot installation failed."
    }

    install_acme() {
            log "Installing acme.sh..."
            curl https://get.acme.sh | sh || { error "Error installing acme.sh, check logs..."; exit 1; }
            ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt &> /dev/null
            check_success "Acme installation completed." "Acme installation failed."
    }

    validate_domain() {
        while true; do
            input "Please enter your domain: " domain
            if [[ "$domain" =~ .*\..* && ${#domain} -ge 3 ]]; then
                return 0
            else
                error "Invalid domain format. Please enter a valid domain name."
            fi
        done
    }

    validate_email() {
        while true; do
            input "Please enter your email: " email
            if [[ "$email" =~ .*@.*\..* && ${#email} -gt 5 ]]; then
                return 0
            else
                error "Invalid email format. Please enter a valid email address."
            fi
        done
    }

       move_ssl_files_combined() {
        local domain="$1"
        local type="$2"
        local dest_dir="$3"


        if [ "$type" == "acme" ]; then
            sudo cp "$HOME/.acme.sh/${domain}_ecc/fullchain.cer" "$dest_dir/fullchain.cer" || { error "Error copying certificate files"; return 1; }
            sudo cp "$HOME/.acme.sh/${domain}_ecc/${domain}.key" "$dest_dir/privkey.key" || { error "Error copying certificate files"; return 1; }
        elif [ "$type" == "certbot" ]; then
            sudo cp "/etc/letsencrypt/live/$domain/fullchain.pem" "$dest_dir/fullchain.pem" || { error "Error copying certificate files"; return 1; }
            sudo cp "/etc/letsencrypt/live/$domain/privkey.pem" "$dest_dir/privkey.pem" || { error "Error copying certificate files"; return 1; }
        fi

        cat "$dest_dir/fullchain.cer" "$dest_dir/privkey.key" > "$dest_dir/certs.pem" || { error "Error creating certs.pem"; return 1; }
        success "SSL certificate files for domain '$domain' successfully moved and combined.\n\n\t⭐ SSL location: $dest_dir\n\n\tcerts.pem: $dest_dir/certs.pem\n"
    }

get_single_ssl() {
    local domain="$1"
    local email="$2"
    local dest_dir="/root/phpliteadmin/certs"

    while true; do
        # Attempt to get SSL certificate using acme.sh
        if sudo ~/.acme.sh/acme.sh --issue --force --standalone -d "$domain" > /dev/null 2>&1; then
            success "⭐ SSL certificate for domain '$domain' successfully obtained using acme.sh."
            move_ssl_files_combined "$domain" "acme" "$dest_dir"
            break
        # Attempt to get SSL certificate using certbot
        elif sudo certbot certonly --standalone -d "$domain" --email "$email" --agree-tos --non-interactive> /dev/null 2>&1; then
            success "⭐ SSL certificate for domain '$domain' successfully obtained using certbot."
            move_ssl_files_combined "$domain" "certbot" "$dest_dir"
            break
        else
            # Inform the user about the failure and re-prompt for domain
            error "Failed to obtain SSL certificate for domain '$domain'. Please check your DNS configuration."
            validate_domain
            domain="$1"
            email="$2"
        fi
    done
}


    update_packages
    install_certbot
    install_acme
    validate_domain
    validate_email
    get_single_ssl "$domain" "$email" 
}



backup_directory() {
    local src_dir="$1"
    local backup_dir="/root/backup_marzban_db/"
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_file="${backup_dir}backup_${timestamp}.tar.gz"

    # Check if source directory exists
    if [ ! -d "$src_dir" ]; then
        error "Source directory '$src_dir' does not exist."
        return 1
    fi

    # Create backup directory if it doesn't exist
    if [ ! -d "$backup_dir" ]; then
        mkdir -p "$backup_dir"
        if [ $? -ne 0 ]; then
            error "Failed to create backup directory '$backup_dir'."
            return 1
        fi
    fi

    # Create the backup
    tar -czf "$backup_file" -C "$(dirname "$src_dir")" "$(basename "$src_dir")"
    if [ $? -eq 0 ]; then
        success "Backup created successfully at '$backup_file'."
        return 0
    else
        error "Failed to create backup."
        return 1
    fi
}

# Example usage:
# copy_directory_contents "/path/to/source/directory" "destination_folder_name"

Uninstall() {
    local docker_file_path="/root/phpliteadmin/docker-compose.yml"
    docker compose -f "$docker_file_path" down || { error "Failed to stop Docker containers."; exit 1; }
    check_success "Docker containers stopped successfully." "Failed to stop Docker containers."
    rm -rf /root/phpliteadmin || { error "Failed to remove phpliteadmin directory."; exit 1; }
    success "phpliteadmin directory removed successfully."
    exit 0
}


create_phpliteadmin_setup() {
    local port="$1"
    local db_path="$2"
    local password="$3"

    # Create directory
    local root_dir="/root/phpliteadmin"
    mkdir -p "$root_dir" || { error "Failed to create directory $root_dir"; exit 1; }

    # Create .env file
    local env_file="$root_dir/.env"
    echo "TZ=Asia/Tehran" > "$env_file"
    echo "PASSWORD=$password" >> "$env_file"
    echo "LOCATION=/db" >> "$env_file"

    # Create docker-compose.yml file
    local compose_file="$root_dir/docker-compose.yml"
    cat <<EOF > "$compose_file"
services:
  phpliteadmin:
    image: 'vtacquet/phpliteadmin'
    hostname: phpliteadmin
    container_name: "phpliteadmin"
    volumes:
      - $db_path:/db
    ports:
      - "$port:80"
    env_file: .env
    restart: 'always'
    networks:
      - monitor

networks:
  monitor:
    driver: bridge
EOF

    success "Setup completed in $root_dir."

}



create_phpliteadmin_haproxy_setup(){

    local port="$1"
    local db_path="$2"
    local password="$3"

    # Create directory
    local root_dir="/root/phpliteadmin"
    mkdir -p "$root_dir" || { error "Failed to create directory $root_dir"; exit 1; }

    # Create .env file
    local env_file="$root_dir/.env"
    echo "TZ=Asia/Tehran" > "$env_file"
    echo "PASSWORD=$password" >> "$env_file"
    echo "LOCATION=/db" >> "$env_file"

    # Create docker-compose.yml file
    local compose_file="$root_dir/docker-compose.yml"
    cat <<EOF > "$compose_file"
services:
  phpliteadmin:
    image: 'vtacquet/phpliteadmin'
    hostname: phpliteadmin
    container_name: "phpliteadmin"
    volumes:
      - $db_path:/db
    expose:
      - "80"
    restart: 'always'
    env_file: .env
    networks:
      - monitor

  haproxy:
    image: haproxytech/haproxy-alpine:2.4
    container_name: haproxysqlite
    volumes:
      - /root/phpliteadmin/haproxy/:/usr/local/etc/haproxy
      - /root/phpliteadmin/certs/:/usr/local/etc/haproxy/certs
    ports:
      - "$port:$port"
    restart: unless-stopped
    networks:
      - monitor

networks:
  monitor:
    driver: bridge

EOF

    # Create docker-compose.yml file
    local haproxy_file="$root_dir/haproxy/haproxy.cfg"
    cat <<EOF > "$haproxy_file"
    # haproxy.cfg
global

        user haproxy
        group haproxy
        daemon

        # See: https://ssl-config.mozilla.org/#server=haproxy&server-version=2.0.3&config=intermediate
        ssl-default-bind-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHAC>
        ssl-default-bind-ciphersuites TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256
        ssl-default-bind-options ssl-min-ver TLSv1.2 no-tls-tickets

defaults
        log     global
        mode    http
        option  httplog
        option  dontlognull
        timeout connect 5000
        timeout client  50000
        timeout server  50000

frontend https_front
    bind *:$port ssl crt /usr/local/etc/haproxy/certs/certs.pem
     mode tcp
    default_backend phpliteadmin_backend

backend phpliteadmin_backend
    server phpliteadmin phpliteadmin:80
EOF


    success "Setup completed in $root_dir."

}


# Start the function


docker_compose_up() {

    local docker_file_path="/root/phpliteadmin/docker-compose.yml"
    docker compose -f "$docker_file_path" up -d || { error "Failed to start Docker containers."; exit 1; }
    check_success "Docker containers started successfully." "Failed to start Docker containers."
    # Check if the containers are running


}
docker_compose_down() {
    local docker_file_path="/root/phpliteadmin/docker-compose.yml"
    docker compose -f "$docker_file_path" down || { error "Failed to stop Docker containers."; exit 1; }
    check_success "Docker containers stopped successfully." "Failed to stop Docker containers."

}
docker_compose_restart() {
    local docker_file_path="/root/phpliteadmin/docker-compose.yml"
    docker compose -f "$docker_file_path" restart || { error "Failed to restart Docker containers."; exit 1; }
    check_success "Docker containers restarted successfully." "Failed to restart Docker containers."

}
# Installation function
install() {
    local port db_path use_ssl password

    # Get valid port
    while true; do
        input "Enter the port number (1-65535): " port
        if is_valid_port "$port"; then
            success "Port $port selected."
            break
        else
            error "Invalid port number. Please try again."
        fi
    done

    # Get Password
    input "Enter the password for the phpliteadmin: " password
    success "Password selected."

    # Get valid database directory path
    db_path="/var/lib/marzban/"
    while true; do
        input "Enter the database directory path [Default: /var/lib/marzban/]: " user_input
        # Use default path if user input is empty
        if [ -z "$user_input" ]; then
            db_path="/var/lib/marzban/"
        else
            db_path="$user_input"
        fi

        if is_valid_path "$db_path"; then
            success "Database path '$db_path' selected."

            # Perform backup
            backup_directory "$db_path"
            if [ $? -ne 0 ]; then
                error "Backup failed. Exiting."
                exit 1
            fi

            break
        else
            error "Invalid directory path. Please try again."
        fi
    done

    # Ask for SSL usage
    input "Do you want to use SSL certificate? (y/n): " use_ssl
    if [[ "$use_ssl" =~ ^[Yy]$ ]]; then
        success "SSL will be configured."
        make_directory "/root/phpliteadmin/haproxy"
        make_directory "/root/phpliteadmin/certs"
        generate_ssl_certificates 
        create_phpliteadmin_haproxy_setup "$port" "$db_path" "$password"
    else
        log "SSL will not be configured."
        make_directory "/root/phpliteadmin/"
        create_phpliteadmin_setup "$port" "$db_path" "$password"
    fi

    # Confirmation
    docker_compose_up 
    print ""
    print ""
    print ""
    success "PHPLiteAdmin installation completed successfully."
    print ""
    print "___________________________________________"
    print ""
    log "Installation details:"
    print ""
    if [[ "$use_ssl" =~ ^[Yy]$ ]]; then
    print "PHPLiteAdmin URL: https://DOMAIN:$port"
    print "SSL certificate: /root/phpliteadmin/certs/certs.pem"
    else
    print "PHPLiteAdmin URL: http://DOMAIN:$port"   
    fi
    print "Port: $port"
    error "Password: $password #Please keep this password safe. DO NOT SHARE IT WITH ANYONE."
    print ""
    print "Database path: $db_path"
    print "Backup location: /root/backup_marzban_db/"


    # Confirmation
    confirm
}



# Menu function
manage_menu() {
    clear
        print ""
    print ""
    print "      PHPLiteAdmin on MARZBAN Panel" 
    print ""
    print "________________AZAVAXHUMAN________________"  
    print ""
    success "YOUTUBE | TELEGRAM : @DAILYDIGITALSKILLS"
    print ""
    print ""
    log "Manage Menu:"
    print ""
    print "1) Start Docker Containers"
    print "2) Stop Docker Containers"
    print "3) Restart Docker Containers"
    print "0) Back to Main Menu"
    print ""
    input "Choose an option: " option

    case $option in
        1)
            docker_compose_up
            ;;
        2)
            docker_compose_down
            ;;
        3)
            docker_compose_restart
            ;;
        0)
            menu
            ;;
        *)
            error "Invalid option. Please choose a valid option."
            manage_menu
            ;;
    esac
    confirm
    menu
}

menu() {
    clear
    print ""
    print ""
    print "      PHPLiteAdmin on MARZBAN Panel" 
    print ""
    print "________________AZAVAXHUMAN________________"  
    print ""
    success "YOUTUBE | TELEGRAM : @DAILYDIGITALSKILLS"
    print ""
    print "1) Install"
    print "2) Manage"
    print "3) Uninstall"
    print "0) Exit"
    print ""
    input "Choose an option: " option

    case $option in
        0)
            exit 0
            ;;
        1)
            install
            ;;
        2)
            manage_menu
            ;;
        3)
            Uninstall
            confirm
            ;;
        *)
            error "Invalid option. Please choose a valid option."
            menu
            ;;
    esac

    menu
}




# Start the script by showing the menu
menu
