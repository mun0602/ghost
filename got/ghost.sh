#!/bin/bash

# Script tự động cài đặt Ghost trên Ubuntu
# Tác giả: Auto Install Script
# Phiên bản: 1.0

set -e

# Màu sắc cho output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function để hiển thị thông báo
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}"
    echo "=================================="
    echo "    GHOST CMS TỰ ĐỘNG CÀI ĐẶT"
    echo "=================================="
    echo -e "${NC}"
}

# Kiểm tra quyền root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        print_error "Đừng chạy script này với quyền root!"
        exit 1
    fi
}

# Cập nhật hệ thống
update_system() {
    print_status "Cập nhật hệ thống..."
    sudo apt update && sudo apt upgrade -y
    sudo apt install -y curl wget git ufw
}

# Cài đặt Docker
install_docker() {
    print_status "Cài đặt Docker..."
    
    # Gỡ Docker cũ
    sudo apt-get remove -y docker docker-engine docker.io containerd runc || true
    
    # Cài các gói cần thiết
    sudo apt-get install -y ca-certificates curl gnupg lsb-release
    
    # Thêm Docker GPG key
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    
    # Thêm Docker repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Cài Docker
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Thêm user vào group docker
    sudo usermod -aG docker $USER
    
    print_status "Docker đã được cài đặt thành công!"
}

# Cài đặt Nginx
install_nginx() {
    print_status "Cài đặt Nginx..."
    sudo apt install -y nginx
    sudo systemctl enable nginx
    sudo systemctl start nginx
}

# Cài đặt Certbot cho SSL
install_certbot() {
    print_status "Cài đặt Certbot..."
    sudo apt install -y snapd
    sudo snap install core; sudo snap refresh core
    sudo apt remove -y certbot || true
    sudo snap install --classic certbot
    sudo ln -sf /snap/bin/certbot /usr/bin/certbot
}

# Cấu hình Firewall
configure_firewall() {
    print_status "Cấu hình Firewall..."
    sudo ufw --force enable
    sudo ufw allow ssh
    sudo ufw allow 'Nginx Full'
    sudo ufw allow 2368
}

# Thu thập thông tin từ người dùng
gather_info() {
    print_header
    
    # Domain hoặc IP
    echo -e "${YELLOW}1. Cấu hình Domain/IP:${NC}"
    read -p "Nhập domain của bạn (ví dụ: example.com) hoặc IP VPS: " DOMAIN
    
    if [[ $DOMAIN =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        USE_IP=true
        USE_SSL=false
        SITE_URL="http://$DOMAIN:2368"
        print_warning "Sử dụng IP, SSL sẽ bị tắt tự động"
    else
        USE_IP=false
        SITE_URL="https://$DOMAIN"
        # SSL
        echo -e "\n${YELLOW}2. Cấu hình SSL:${NC}"
        read -p "Bạn có muốn cài SSL miễn phí (Let's Encrypt)? (y/n): " ssl_choice
        if [[ $ssl_choice =~ ^[Yy]$ ]]; then
            USE_SSL=true
        else
            USE_SSL=false
            SITE_URL="http://$DOMAIN"
        fi
    fi
    
    # Database
    echo -e "\n${YELLOW}3. Chọn Database:${NC}"
    echo "1) SQLite (Đơn giản, phù hợp blog nhỏ)"
    echo "2) MySQL (Mạnh mẽ, phù hợp blog lớn)"
    read -p "Chọn (1/2): " db_choice
    
    if [[ $db_choice == "2" ]]; then
        USE_MYSQL=true
        read -p "Nhập mật khẩu MySQL root: " MYSQL_ROOT_PASSWORD
        read -p "Nhập mật khẩu database Ghost: " GHOST_DB_PASSWORD
    else
        USE_MYSQL=false
    fi
    
    # Email cho SSL
    if [[ $USE_SSL == true ]]; then
        read -p "Nhập email để đăng ký SSL: " SSL_EMAIL
    fi
    
    # Xác nhận thông tin
    echo -e "\n${BLUE}=== XÁC NHẬN THÔNG TIN ===${NC}"
    echo "Domain/IP: $DOMAIN"
    echo "URL trang web: $SITE_URL"
    echo "Database: $([ $USE_MYSQL == true ] && echo 'MySQL' || echo 'SQLite')"
    echo "SSL: $([ $USE_SSL == true ] && echo 'Có' || echo 'Không')"
    echo
    read -p "Thông tin có đúng không? (y/n): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        print_error "Hủy cài đặt!"
        exit 1
    fi
}

# Tạo thư mục dự án
create_project_dir() {
    print_status "Tạo thư mục dự án..."
    PROJECT_DIR="/home/$USER/ghost-blog"
    mkdir -p $PROJECT_DIR
    cd $PROJECT_DIR
}

# Tạo docker-compose.yml
create_docker_compose() {
    print_status "Tạo file docker-compose.yml..."
    
    if [[ $USE_MYSQL == true ]]; then
        # Ghost với MySQL
        cat > docker-compose.yml << EOF
version: '3.8'

services:
  ghost:
    image: ghost:latest
    restart: always
    ports:
      - "127.0.0.1:2368:2368"
    environment:
      url: $SITE_URL
      database__client: mysql
      database__connection__host: db
      database__connection__user: ghost
      database__connection__password: $GHOST_DB_PASSWORD
      database__connection__database: ghostdb
      mail__transport: SMTP
    volumes:
      - ghost_content:/var/lib/ghost/content
    depends_on:
      - db

  db:
    image: mysql:8.0
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: $MYSQL_ROOT_PASSWORD
      MYSQL_DATABASE: ghostdb
      MYSQL_USER: ghost
      MYSQL_PASSWORD: $GHOST_DB_PASSWORD
    volumes:
      - ghost_mysql:/var/lib/mysql

volumes:
  ghost_content:
  ghost_mysql:
EOF
    else
        # Ghost với SQLite
        cat > docker-compose.yml << EOF
version: '3.8'

services:
  ghost:
    image: ghost:latest
    restart: always
    ports:
      - "127.0.0.1:2368:2368"
    environment:
      url: $SITE_URL
      mail__transport: SMTP
    volumes:
      - ghost_content:/var/lib/ghost/content

volumes:
  ghost_content:
EOF
    fi
}

# Cấu hình Nginx
configure_nginx() {
    print_status "Cấu hình Nginx..."
    
    # Tạo config Nginx
    sudo tee /etc/nginx/sites-available/ghost << EOF
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:2368;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

    # Kích hoạt site
    sudo ln -sf /etc/nginx/sites-available/ghost /etc/nginx/sites-enabled/
    sudo rm -f /etc/nginx/sites-enabled/default
    sudo nginx -t
    sudo systemctl reload nginx
}

# Cài đặt SSL
setup_ssl() {
    if [[ $USE_SSL == true ]]; then
        print_status "Cài đặt SSL Certificate..."
        sudo certbot --nginx -d $DOMAIN --email $SSL_EMAIL --agree-tos --non-interactive
        
        # Auto renewal
        echo "0 12 * * * /usr/bin/certbot renew --quiet" | sudo crontab -
    fi
}

# Khởi động Ghost
start_ghost() {
    print_status "Khởi động Ghost..."
    cd $PROJECT_DIR
    docker compose up -d
    
    # Chờ Ghost khởi động
    print_status "Chờ Ghost khởi động..."
    sleep 30
}

# Hiển thị thông tin hoàn thành
show_completion_info() {
    print_header
    echo -e "${GREEN}🎉 GHOST ĐÃ ĐƯỢC CÀI ĐẶT THÀNH CÔNG! 🎉${NC}"
    echo
    echo -e "${BLUE}Thông tin truy cập:${NC}"
    echo "📱 Trang web: $SITE_URL"
    echo "⚙️  Admin panel: $SITE_URL/ghost"
    echo
    echo -e "${BLUE}Thông tin kỹ thuật:${NC}"
    echo "📁 Thư mục dự án: $PROJECT_DIR"
    echo "🗄️  Database: $([ $USE_MYSQL == true ] && echo 'MySQL' || echo 'SQLite')"
    echo "🔒 SSL: $([ $USE_SSL == true ] && echo 'Đã kích hoạt' || echo 'Chưa kích hoạt')"
    echo
    echo -e "${YELLOW}Các lệnh hữu ích:${NC}"
    echo "• Xem logs: cd $PROJECT_DIR && docker compose logs -f"
    echo "• Dừng Ghost: cd $PROJECT_DIR && docker compose down"
    echo "• Khởi động Ghost: cd $PROJECT_DIR && docker compose up -d"
    echo "• Cập nhật Ghost: cd $PROJECT_DIR && docker compose pull && docker compose up -d"
    echo
    echo -e "${GREEN}Bây giờ bạn có thể truy cập $SITE_URL/ghost để thiết lập tài khoản admin!${NC}"
}

# Main function
main() {
    print_header
    print_status "Bắt đầu cài đặt Ghost CMS..."
    
    check_root
    gather_info
    update_system
    install_docker
    install_nginx
    
    if [[ $USE_SSL == true ]]; then
        install_certbot
    fi
    
    configure_firewall
    create_project_dir
    create_docker_compose
    configure_nginx
    
    # Restart lại để group docker có hiệu lực
    print_warning "Cần logout và login lại để sử dụng Docker, hoặc chạy lệnh: newgrp docker"
    read -p "Nhấn Enter để tiếp tục sau khi logout/login..."
    
    start_ghost
    
    if [[ $USE_SSL == true ]]; then
        setup_ssl
    fi
    
    show_completion_info
}

# Chạy script
main "$@"