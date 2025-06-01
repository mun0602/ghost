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
    echo "     TỰ ĐỘNG TẠO USER & CÀI ĐẶT"
    echo "========================================"
    echo -e "${NC}"
}

# Hiển thị hướng dẫn sử dụng
show_usage() {
    echo "Cách sử dụng:"
    echo ""
    echo "🔧 CÁCH 1: CHẠY VỚI ROOT (KHUYÊN DÙNG - DỄ NHẤT):"
    echo "   sudo ./ghost-official-install.sh"
    echo "   → Script tự tạo user mới và cài đặt hoàn toàn tự động"
    echo "   → Không cần tạo user trước"
    echo "   → Không cần cấu hình sudo"
    echo ""
    echo "🔧 CÁCH 2: CHẠY VỚI USER THƯỜNG:"
    echo "   ./ghost-official-install.sh"
    echo "   → User phải có quyền sudo"
    echo "   → Kiểm tra: sudo -l"
    echo ""
    echo "🔧 CÁCH 3: TẠO USER TRƯỚC RỒI CHẠY:"
    echo "   sudo adduser myuser"
    echo "   sudo usermod -aG sudo myuser"
    echo "   su - myuser"
    echo "   ./ghost-official-install.sh"
    echo ""
    echo "📋 YÊU CẦU:"
    echo "   • Ubuntu 20.04/22.04/24.04"
    echo "   • Kết nối internet ổn định"
    echo "   • Domain đã trỏ về IP VPS (cho SSL)"
    echo "   • Port 80, 443, 2368 mở"
    echo ""
    echo "❓ TẠI SAO CẦN USER RIÊNG:"
    echo "   • Ghost-CLI không hoạt động với root"
    echo "   • Bảo mật: mỗi service một user"
    echo "   • Production best practice"
    echo ""
    echo "🆘 KHẮC PHỤC LỖI SUDO:"
    echo "   • Thêm sudo: sudo usermod -aG sudo \$USER"
    echo "   • Logout/login lại: exit && ssh user@server"  
    echo "   • Hoặc: newgrp sudo"
    echo ""
}

# Kiểm tra quyền root và tạo user
check_user() {
    if [[ $EUID -eq 0 ]]; then
        print_status "Đang chạy với quyền root - OK!"
        echo
        echo -e "${YELLOW}⚠️  TẠI SAO CẦN USER RIÊNG?${NC}"
        echo "• Ghost không nên chạy với root vì lý do bảo mật"
        echo "• Ghost-CLI yêu cầu user thường (không phải root)"
        echo "• Production best practice: dùng user riêng cho mỗi service"
        echo
        echo "Tùy chọn:"
        echo "1) Tạo user mới tự động (khuyên dùng)"
        echo "2) Sử dụng user hiện có"
        echo "3) Tiếp tục với root (không khuyên)"
        echo "4) Hủy"
        read -p "Chọn (1/2/3/4): " user_choice
        
        case $user_choice in
            1) create_new_user ;;
            2) switch_to_existing_user ;;
            3) 
                print_warning "Tiếp tục với root - KHÔNG KHUYÊN DÙNG!"
                print_warning "Ghost có thể hoạt động không ổn định"
                read -p "Bạn có chắc? (y/N): " confirm_root
                if [[ ! $confirm_root =~ ^[Yy]$ ]]; then
                    exit 0
                fi
                # Tiếp tục với root
                ;;
            4) echo "❌ Hủy!"; exit 0 ;;
            *) print_error "Lựa chọn không hợp lệ!"; exit 1 ;;
        esac
    else
        # Kiểm tra user hiện tại
        check_current_user
    fi
}

# Tạo user mới
create_new_user() {
    print_status "Tạo user mới..."
    
    # Lấy tên user
    read -p "Nhập tên user mới (ví dụ: myuser): " NEW_USER
    
    # Validate tên user
    if [[ -z "$NEW_USER" || "$NEW_USER" == "ghost" || "$NEW_USER" == "root" ]]; then
        print_error "Tên user không hợp lệ! Không được dùng 'ghost' hoặc 'root'"
        exit 1
    fi
    
    if id "$NEW_USER" &>/dev/null; then
        print_warning "User $NEW_USER đã tồn tại"
        read -p "Sử dụng user này? (y/n): " use_existing
        if [[ ! $use_existing =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        # Tạo user mới với password tự động
        print_status "Tạo user: $NEW_USER"
        
        # Tạo password ngẫu nhiên cho user
        NEW_USER_PASSWORD=$(openssl rand -base64 12)
        
        # Tạo user không interactive
        useradd -m -s /bin/bash "$NEW_USER"
        echo "$NEW_USER:$NEW_USER_PASSWORD" | chpasswd
        
        echo "✅ User $NEW_USER đã được tạo"
        echo "🔑 Password: $NEW_USER_PASSWORD"
        echo "📝 (Ghi nhớ để login SSH sau này)"
        
        if [[ $? -ne 0 ]]; then
            print_error "Không thể tạo user!"
            exit 1
        fi
    fi
    
    # Thêm vào sudo group
    usermod -aG sudo "$NEW_USER"
    echo "✅ Đã thêm $NEW_USER vào sudo group"
    
    # Tạo script cho user mới và chạy
    print_status "Tiếp tục cài đặt với user: $NEW_USER"
    
    # Copy script đến home của user mới
    local script_path="/home/$NEW_USER/ghost-install.sh"
    cp "$0" "$script_path"
    chown "$NEW_USER:$NEW_USER" "$script_path"
    chmod +x "$script_path"
    
    # Chạy script với user mới (không cần su interactively)
    print_status "Chuyển sang user $NEW_USER và tiếp tục..."
    
    # Export các biến môi trường để user mới có thể dùng
    export GHOST_AUTO_CONTINUE=1
    runuser -l "$NEW_USER" -c "$script_path --continue"
    exit 0
}

# Chuyển sang user hiện có
switch_to_existing_user() {
    print_status "Chọn user hiện có..."
    
    # Hiển thị danh sách users
    echo "Danh sách users có thể sử dụng:"
    local users=($(awk -F: '$3 >= 1000 && $3 < 65534 && $1 != "nobody" {print $1}' /etc/passwd))
    
    if [[ ${#users[@]} -eq 0 ]]; then
        print_warning "Không tìm thấy user phù hợp!"
        echo "Tạo user mới thay thế?"
        read -p "(y/n): " create_new
        if [[ $create_new =~ ^[Yy]$ ]]; then
            create_new_user
        else
            exit 1
        fi
        return
    fi
    
    local i=1
    for user in "${users[@]}"; do
        # Hiển thị thêm thông tin user
        local user_info=$(getent passwd "$user" | cut -d: -f5)
        echo "$i) $user $([ -n "$user_info" ] && echo "($user_info)")"
        ((i++))
    done
    echo "0) Tạo user mới"
    
    read -p "Chọn user (0-${#users[@]}): " user_index
    
    if [[ $user_index -eq 0 ]]; then
        create_new_user
        return
    elif [[ $user_index -lt 1 || $user_index -gt ${#users[@]} ]]; then
        print_error "Lựa chọn không hợp lệ!"
        exit 1
    fi
    
    local selected_user="${users[$((user_index-1))]}"
    
    # Đảm bảo user có sudo
    usermod -aG sudo "$selected_user" 2>/dev/null || true
    echo "✅ Đã thêm $selected_user vào sudo group"
    
    # Copy script và chuyển user
    local script_path="/home/$selected_user/ghost-install.sh"
    cp "$0" "$script_path"
    chown "$selected_user:$selected_user" "$script_path"
    chmod +x "$script_path"
    
    print_status "Chuyển sang user: $selected_user"
    export GHOST_AUTO_CONTINUE=1
    runuser -l "$selected_user" -c "$script_path --continue"
    exit 0
}

# Kiểm tra user hiện tại
check_current_user() {
    if [[ "$USER" == "ghost" ]]; then
        print_error "Không được dùng user tên 'ghost'!"
        print_warning "Ghost-CLI không hoạt động với user tên 'ghost'"
        echo
        echo "Giải pháp:"
        echo "1) Tạo user mới: sudo adduser myuser && sudo usermod -aG sudo myuser"
        echo "2) Đổi tên user hiện tại"
        echo "3) Chạy script với root để tự tạo user"
        exit 1
    fi
    
    # Kiểm tra sudo
    print_status "Kiểm tra quyền sudo cho user: $USER"
    
    if sudo -n true 2>/dev/null; then
        print_status "✅ User $USER có quyền sudo"
        return 0
    fi
    
    print_warning "User $USER chưa có quyền sudo"
    echo
    echo "Cách khắc phục:"
    echo "1) Thêm sudo: su -c 'usermod -aG sudo $USER' root"
    echo "2) Logout/login lại: exit && ssh user@server"
    echo "3) Chạy: newgrp sudo"
    echo "4) Hoặc chạy script với root để tự tạo user mới"
    echo
    
    read -p "Thử thêm quyền sudo ngay? (cần password root) (y/n): " try_sudo
    
    if [[ $try_sudo =~ ^[Yy]$ ]]; then
        echo "Nhập password root để thêm quyền sudo:"
        if su -c "usermod -aG sudo $USER" root; then
            echo "✅ Đã thêm quyền sudo"
            echo "⚠️  Cần logout/login lại để có hiệu lực"
            echo
            read -p "Tiếp tục? (script có thể lỗi nếu chưa logout/login) (y/n): " continue_anyway
            if [[ ! $continue_anyway =~ ^[Yy]$ ]]; then
                echo "Hãy logout/login rồi chạy lại script"
                exit 0
            fi
        else
            print_error "Không thể thêm quyền sudo"
            exit 1
        fi
    else
        print_error "Cần quyền sudo để tiếp tục"
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
    
    # Khai báo biến global
    declare -g DOMAIN SITENAME MYSQL_ROOT_PASSWORD USE_SSL SSL_EMAIL BLOG_URL pass_choice
    
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
    echo "1) Tự động tạo mật khẩu"
    echo "2) Nhập mật khẩu thủ công"
    read -p "Chọn (1/2): " pass_choice
    
    if [[ "$pass_choice" == "1" ]]; then
        MYSQL_ROOT_PASSWORD=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-12)
        echo "✅ Mật khẩu tự động: $MYSQL_ROOT_PASSWORD"
        echo "📝 (Ghi nhớ mật khẩu này!)"
        read -p "Nhấn Enter để tiếp tục..." -t 10
    else
        read -s -p "Nhập mật khẩu MySQL root: " MYSQL_ROOT_PASSWORD
        echo
    fi
    
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
    if [[ "$pass_choice" == "1" ]]; then
        echo "MySQL root password: $MYSQL_ROOT_PASSWORD (tự động tạo)"
    else
        echo "MySQL root password: [đã đặt thủ công]"
    fi
    echo "SSL: $([ $USE_SSL = 'y' ] && echo 'Có' || echo 'Không')"
    echo "User hiện tại: $USER"
    echo ""
    echo "⚠️  Script sẽ cài đặt:"
    echo "   • NGINX (web server)"
    echo "   • MySQL 8 (database)"  
    echo "   • Node.js 18 (runtime)"
    echo "   • Ghost-CLI (quản lý)"
    echo "   • Ghost CMS (production)"
    echo ""
    read -p "Bắt đầu cài đặt? (y/n): " confirm
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
    echo "🔑 MySQL root password: [đã lưu trong config]"
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
    # Kiểm tra tham số
    case "$1" in
        --help|-h)
            print_header
            show_usage
            exit 0
            ;;
        --continue)
            print_header
            print_status "Tiếp tục cài đặt Ghost với user: $USER"
            
            # Bỏ qua bước tạo user, chuyển thẳng đến gather_info
            check_current_user
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
            ;;
        "")
            # Chạy bình thường
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
            ;;
        *)
            print_error "Tham số không hợp lệ: $1"
            echo "Sử dụng: $0 [--help|--continue]"
            exit 1
            ;;
    esac
}

# Chạy script
main "$@"
