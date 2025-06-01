#!/bin/bash

# Script cài đặt Ghost theo hướng dẫn chính thức ghost.org
# Ubuntu 20.04/22.04 + NGINX + MySQL + Node.js + Ghost-CLI
# Phiên bản: 1.0

set -e

# Màu sắc
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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
    echo "========================================"
    echo "    GHOST CÀI ĐẶT CHÍNH THỨC"
    echo "   Ubuntu + NGINX + MySQL + Node.js"
    echo "========================================"
    echo -e "${NC}"
}

# Kiểm tra quyền root
check_user() {
    if [[ $EUID -eq 0 ]]; then
        print_error "Script này không nên chạy với quyền root!"
        print_warning "Hãy tạo user mới hoặc chạy với user thường"
        echo "Tạo user mới:"
        echo "  sudo adduser yourname"
        echo "  sudo usermod -aG sudo yourname"
        echo "  su - yourname"
        exit 1
    fi
    
    # Kiểm tra sudo
    if ! sudo -n true 2>/dev/null; then
        print_warning "User hiện tại cần có quyền sudo"
        echo "Thêm quyền sudo:"
        echo "  sudo usermod -aG sudo $USER"
        exit 1
    fi
}

# Kiểm tra OS
check_os() {
    if [[ ! -f /etc/os-release ]]; then
        print_error "Không thể xác định OS"
        exit 1
    fi
    
    source /etc/os-release
    if [[ "$ID" != "ubuntu" ]]; then
        print_error "Script này chỉ hỗ trợ Ubuntu"
        exit 1
    fi
    
    local version=$(echo $VERSION_ID | cut -d. -f1)
    if [[ "$version" != "20" && "$version" != "22" && "$version" != "24" ]]; then
        print_warning "Ghost chính thức hỗ trợ Ubuntu 20.04/22.04. Phiên bản hiện tại: $VERSION_ID"
        read -p "Tiếp tục? (y/n): " continue_choice
        if [[ ! $continue_choice =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Thu thập thông tin
gather_info() {
    print_header
    
    print_status "Thu thập thông tin cài đặt..."
    
    # Domain
    echo -e "${YELLOW}1. Cấu hình Domain:${NC}"
    read -p "Nhập domain của bạn (ví dụ: myblog.com): " DOMAIN
    
    if [[ ! $DOMAIN =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]\.[a-zA-Z]{2,}$ ]]; then
        print_warning "Domain không hợp lệ, nhưng sẽ tiếp tục..."
    fi
    
    # Site name
    echo -e "\n${YELLOW}2. Tên trang web:${NC}"
    read -p "Nhập tên thư mục (ví dụ: myblog): " SITENAME
    SITENAME=${SITENAME//[^a-zA-Z0-9]/}  # Loại bỏ ký tự đặc biệt
    
    if [[ -z "$SITENAME" ]]; then
        SITENAME="ghostsite"
    fi
    
    # MySQL password
    echo -e "\n${YELLOW}3. Mật khẩu MySQL:${NC}"
    read -s -p "Nhập mật khẩu MySQL root: " MYSQL_ROOT_PASSWORD
    echo
    
    if [[ ${#MYSQL_ROOT_PASSWORD} -lt 6 ]]; then
        print_error "Mật khẩu MySQL phải ít nhất 6 ký tự!"
        exit 1
    fi
    
    # SSL
    echo -e "\n${YELLOW}4. SSL Certificate:${NC}"
    read -p "Cài đặt SSL (Let's Encrypt)? (y/n): " USE_SSL
    
    if [[ $USE_SSL =~ ^[Yy]$ ]]; then
        read -p "Nhập email cho SSL: " SSL_EMAIL
        BLOG_URL="https://$DOMAIN"
    else
        BLOG_URL="http://$DOMAIN"
    fi
    
    # Xác nhận
    echo -e "\n${BLUE}=== XÁC NHẬN THÔNG TIN ===${NC}"
    echo "Domain: $DOMAIN"
    echo "Blog URL: $BLOG_URL"
    echo "Site name: $SITENAME"
    echo "Thư mục: /var/www/$SITENAME"
    echo "MySQL root password: [đã đặt]"
    echo "SSL: $([ $USE_SSL = 'y' ] && echo 'Có' || echo 'Không')"
    echo
    read -p "Thông tin có đúng không? (y/n): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        print_error "Hủy cài đặt!"
        exit 1
    fi
}

# Kiểm tra cài đặt cũ
check_existing() {
    print_status "Kiểm tra cài đặt cũ..."
    
    local has_existing=false
    
    # Kiểm tra Ghost-CLI
    if command -v ghost >/dev/null 2>&1; then
        echo "⚠️  Tìm thấy Ghost-CLI"
        has_existing=true
    fi
    
    # Kiểm tra thư mục
    if [[ -d "/var/www/$SITENAME" ]]; then
        echo "⚠️  Thư mục /var/www/$SITENAME đã tồn tại"
        has_existing=true
    fi
    
    # Kiểm tra NGINX
    if systemctl is-active --quiet nginx 2>/dev/null; then
        echo "⚠️  NGINX đang chạy"
        has_existing=true
    fi
    
    # Kiểm tra MySQL
    if systemctl is-active --quiet mysql 2>/dev/null; then
        echo "⚠️  MySQL đang chạy"
        has_existing=true
    fi
    
    if [[ "$has_existing" = true ]]; then
        echo ""
        print_warning "Phát hiện cài đặt cũ!"
        echo "1) Tiếp tục (có thể gây conflict)"
        echo "2) Dọn dẹp và cài mới"
        echo "3) Hủy"
        read -p "Chọn (1/2/3): " choice
        
        case $choice in
            1) echo "⏩ Tiếp tục..." ;;
            2) cleanup_existing ;;
            3) echo "❌ Hủy!"; exit 0 ;;
            *) print_error "Lựa chọn không hợp lệ!"; exit 1 ;;
        esac
    fi
}

# Dọn dẹp cài đặt cũ
cleanup_existing() {
    print_status "Dọn dẹp cài đặt cũ..."
    
    # Dừng Ghost nếu đang chạy
    if [[ -d "/var/www/$SITENAME" ]]; then
        cd "/var/www/$SITENAME"
        sudo -u $USER ghost stop 2>/dev/null || true
        sudo -u $USER ghost uninstall --force 2>/dev/null || true
    fi
    
    # Xóa thư mục
    if [[ -d "/var/www/$SITENAME" ]]; then
        sudo rm -rf "/var/www/$SITENAME"
        echo "✅ Đã xóa /var/www/$SITENAME"
    fi
    
    # Gỡ Ghost-CLI
    sudo npm uninstall -g ghost-cli 2>/dev/null || true
    echo "✅ Đã gỡ Ghost-CLI"
}

# Cập nhật hệ thống
update_system() {
    print_status "Cập nhật hệ thống..."
    sudo apt-get update
    sudo apt-get upgrade -y
    sudo apt-get install -y curl wget gnupg2 software-properties-common
}

# Cài đặt NGINX
install_nginx() {
    print_status "Cài đặt NGINX..."
    sudo apt-get install -y nginx
    
    # Kiểm tra version
    local nginx_version=$(nginx -v 2>&1 | grep -o '[0-9.]*')
    echo "✅ NGINX $nginx_version đã cài đặt"
    
    # Khởi động và enable
    sudo systemctl start nginx
    sudo systemctl enable nginx
    
    # Cấu hình firewall
    sudo ufw allow 'Nginx Full' 2>/dev/null || true
    echo "✅ NGINX đã được cấu hình"
}

# Cài đặt MySQL
install_mysql() {
    print_status "Cài đặt MySQL..."
    
    # Set root password trước khi cài
    echo "mysql-server mysql-server/root_password password $MYSQL_ROOT_PASSWORD" | sudo debconf-set-selections
    echo "mysql-server mysql-server/root_password_again password $MYSQL_ROOT_PASSWORD" | sudo debconf-set-selections
    
    sudo apt-get install -y mysql-server
    
    # Khởi động MySQL
    sudo systemctl start mysql
    sudo systemctl enable mysql
    
    # Cấu hình MySQL cho Ghost
    print_status "Cấu hình MySQL..."
    
    # Tạo script SQL
    cat > /tmp/mysql_setup.sql << EOF
ALTER USER 'root'@'localhost' IDENTIFIED WITH 'mysql_native_password' BY '$MYSQL_ROOT_PASSWORD';
FLUSH PRIVILEGES;
EOF
    
    # Chạy script
    mysql -u root -p"$MYSQL_ROOT_PASSWORD" < /tmp/mysql_setup.sql 2>/dev/null || {
        # Nếu lỗi, thử không có password
        sudo mysql < /tmp/mysql_setup.sql
    }
    
    rm /tmp/mysql_setup.sql
    echo "✅ MySQL đã được cấu hình"
}

# Cài đặt Node.js
install_nodejs() {
    print_status "Cài đặt Node.js..."
    
    # Thêm NodeSource repository
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
    
    # Sử dụng Node.js 18 (LTS được Ghost hỗ trợ)
    NODE_MAJOR=18
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" | sudo tee /etc/apt/sources.list.d/nodesource.list
    
    sudo apt-get update
    sudo apt-get install -y nodejs
    
    # Kiểm tra version
    local node_version=$(node --version)
    local npm_version=$(npm --version)
    echo "✅ Node.js $node_version, npm $npm_version đã cài đặt"
}

# Cài đặt Ghost-CLI
install_ghost_cli() {
    print_status "Cài đặt Ghost-CLI..."
    sudo npm install ghost-cli@latest -g
    
    # Kiểm tra
    local ghost_cli_version=$(ghost --version)
    echo "✅ Ghost-CLI $ghost_cli_version đã cài đặt"
}

# Tạo thư mục và cài Ghost
install_ghost() {
    print_status "Tạo thư mục và cài đặt Ghost..."
    
    # Tạo thư mục
    sudo mkdir -p "/var/www/$SITENAME"
    sudo chown $USER:$USER "/var/www/$SITENAME"
    sudo chmod 775 "/var/www/$SITENAME"
    
    cd "/var/www/$SITENAME"
    
    # Cài Ghost với auto-config
    print_status "Chạy Ghost install..."
    print_warning "Quá trình này có thể mất 5-10 phút..."
    
    # Tạo file config tự động
    cat > .ghost-cli << EOF
{
  "instances": {
    "default": {
      "url": "$BLOG_URL",
      "adminUrl": "$BLOG_URL",
      "database": {
        "client": "mysql",
        "connection": {
          "host": "localhost",
          "user": "root",
          "password": "$MYSQL_ROOT_PASSWORD",
          "database": "ghost_prod"
        }
      },
      "server": {
        "port": 2368,
        "host": "127.0.0.1"
      },
      "process": "systemd",
      "paths": {
        "contentPath": "content"
      }
    }
  }
}
EOF
    
    # Chạy ghost install với các flags
    ghost install \
        --url "$BLOG_URL" \
        --db mysql \
        --dbhost localhost \
        --dbuser root \
        --dbpass "$MYSQL_ROOT_PASSWORD" \
        --dbname "ghost_prod" \
        --process systemd \
        --nginx \
        $([ "$USE_SSL" = "y" ] && echo "--ssl --sslemail $SSL_EMAIL" || echo "--no-ssl") \
        --no-prompt
}

# Kiểm tra cài đặt
verify_installation() {
    print_status "Kiểm tra cài đặt..."
    
    cd "/var/www/$SITENAME"
    
    # Kiểm tra Ghost service
    if ghost status | grep -q "running"; then
        echo "✅ Ghost service đang chạy"
    else
        echo "❌ Ghost service không chạy"
        return 1
    fi
    
    # Kiểm tra URL
    sleep 5
    if curl -s --connect-timeout 10 "$BLOG_URL" >/dev/null; then
        echo "✅ Website phản hồi tại $BLOG_URL"
    else
        echo "⚠️  Website chưa phản hồi (có thể cần thời gian)"
    fi
    
    # Kiểm tra admin
    if curl -s --connect-timeout 10 "$BLOG_URL/ghost" >/dev/null; then
        echo "✅ Admin panel khả dụng tại $BLOG_URL/ghost"
    else
        echo "⚠️  Admin panel chưa khả dụng"
    fi
    
    return 0
}

# Hiển thị kết quả
show_completion() {
    print_header
    echo -e "${GREEN}🎉 GHOST ĐÃ ĐƯỢC CÀI ĐẶT THÀNH CÔNG! 🎉${NC}"
    echo
    echo -e "${BLUE}Thông tin truy cập:${NC}"
    echo "🌐 Website: $BLOG_URL"
    echo "⚙️  Admin: $BLOG_URL/ghost"
    echo
    echo -e "${BLUE}Thông tin kỹ thuật:${NC}"
    echo "📁 Thư mục: /var/www/$SITENAME"
    echo "🗄️  Database: MySQL (ghost_prod)"
    echo "🔒 SSL: $([ $USE_SSL = 'y' ] && echo 'Đã kích hoạt' || echo 'Chưa kích hoạt')"
    echo "🌐 Web server: NGINX"
    echo "⚙️  Process: systemd"
    echo
    echo -e "${YELLOW}Lệnh quản lý Ghost:${NC}"
    echo "• Xem status: cd /var/www/$SITENAME && ghost status"
    echo "• Khởi động: cd /var/www/$SITENAME && ghost start"
    echo "• Dừng: cd /var/www/$SITENAME && ghost stop"
    echo "• Khởi động lại: cd /var/www/$SITENAME && ghost restart"
    echo "• Cập nhật: cd /var/www/$SITENAME && ghost update"
    echo "• Xem logs: cd /var/www/$SITENAME && ghost log"
    echo
    echo -e "${YELLOW}Cấu hình bổ sung:${NC}"
    echo "• SSL sau: cd /var/www/$SITENAME && ghost setup ssl"
    echo "• Nginx config: /etc/nginx/sites-available/$SITENAME-ssl.conf"
    echo "• Ghost config: /var/www/$SITENAME/config.production.json"
    echo
    echo -e "${GREEN}Bây giờ truy cập $BLOG_URL/ghost để tạo tài khoản admin!${NC}"
}

# Main function
main() {
    print_header
    print_status "Bắt đầu cài đặt Ghost theo hướng dẫn chính thức..."
    
    check_user
    check_os
    gather_info
    check_existing
    update_system
    install_nginx
    install_mysql
    install_nodejs
    install_ghost_cli
    install_ghost
    
    if verify_installation; then
        show_completion
    else
        print_error "Cài đặt có lỗi. Kiểm tra logs:"
        echo "cd /var/www/$SITENAME && ghost log"
    fi
}

# Chạy script
main "$@"
