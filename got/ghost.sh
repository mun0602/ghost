#!/bin/bash

# Script cài Ghost đơn giản
echo "=== GHOST CÀI ĐẶT ĐƠN GIẢN ==="

# Cập nhật package list
echo "1. Cập nhật package list..."
sudo apt update
sudo apt install -y curl wget net-tools iproute2

# Kiểm tra cài đặt cũ
# Hiển thị thông tin cài đặt hiện tại
show_current_info() {
    echo ""
    echo "=== THÔNG TIN CÀI ĐẶT HIỆN TẠI ==="
    
    # Thông tin containers
    if docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" | grep -E "ghost|db"; then
        echo "🐳 Docker Containers:"
        docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" | grep -E "ghost|db"
    fi
    
    # Thông tin volumes
    if docker volume ls | grep -E "ghost|db"; then
        echo ""
        echo "💾 Docker Volumes:"
        docker volume ls | grep -E "ghost|db"
    fi
    
    # Thông tin cấu hình
    if [ -f "$HOME/ghost/docker-compose.yml" ]; then
        echo ""
        echo "📄 Config hiện tại (~/ghost/docker-compose.yml):"
        echo "----------------------------------------"
        cat "$HOME/ghost/docker-compose.yml"
        echo "----------------------------------------"
    fi
    
    # Thông tin URL
    echo ""
    echo "🌐 Kiểm tra kết nối:"
    local ports=("2368" "8080")
    for port in "${ports[@]}"; do
        if ss -tuln | grep -q ":$port"; then
            echo "   Port $port: ✅ Đang mở"
            local public_ip=$(curl -s --connect-timeout 5 ifconfig.me || echo "UNKNOWN")
            echo "   URL có thể: http://$public_ip:$port"
        fi
    done
    
    echo ""
    echo "📁 Thư mục: $([ -d "$HOME/ghost" ] && echo "✅ ~/ghost/ tồn tại" || echo "❌ ~/ghost/ không tồn tại")"
    
    echo ""
    echo "Press Enter để tiếp tục..."
    read
}

# Restore từ backup
restore_from_backup() {
    echo ""
    echo "=== RESTORE TỪ BACKUP ==="
    echo "📁 Các backup có sẵn:"
    
    local backup_dirs=($(ls -d $HOME/ghost-backup-* 2>/dev/null || true))
    
    if [ ${#backup_dirs[@]} -eq 0 ]; then
        echo "❌ Không tìm thấy backup nào!"
        return 1
    fi
    
    local i=1
    for dir in "${backup_dirs[@]}"; do
        echo "$i) $(basename $dir)"
        ((i++))
    done
    
    echo "0) Hủy"
    echo ""
    read -p "Chọn backup để restore: " choice
    
    if [[ "$choice" == "0" ]]; then
        return 0
    fi
    
    local selected_backup="${backup_dirs[$((choice-1))]}"
    
    if [ -z "$selected_backup" ]; then
        echo "❌ Lựa chọn không hợp lệ!"
        return 1
    fi
    
    echo "🔄 Restore từ: $(basename $selected_backup)"
    
    # Restore config
    if [ -d "$selected_backup" ]; then
        cp -r "$selected_backup"/* "$HOME/ghost/" 2>/dev/null || true
        echo "✅ Restore config"
    fi
    
    # Restore content volume
    if [ -f "$selected_backup/ghost_content.tar.gz" ]; then
        docker volume create ghost_content
        docker run --rm -v ghost_content:/data -v "$selected_backup":/backup alpine tar xzf /backup/ghost_content.tar.gz -C /data
        echo "✅ Restore content volume"
    fi
    
    echo "✅ Restore hoàn tất!"
}

check_existing_installation() {
    echo ""
    echo "=== KIỂM TRA CÀI ĐẶT CŨ ==="
    
    local has_old_install=false
    
    # Kiểm tra thư mục ~/ghost
    if [ -d "$HOME/ghost" ]; then
        echo "📁 Tìm thấy thư mục: ~/ghost/"
        has_old_install=true
    fi
    
    # Kiểm tra containers Ghost đang chạy
    if docker ps -a --format "table {{.Names}}" 2>/dev/null | grep -q ghost; then
        echo "🐳 Tìm thấy Ghost containers:"
        docker ps -a --format "table {{.Names}}\t{{.Status}}" | grep ghost
        has_old_install=true
    fi
    
    # Kiểm tra volumes
    if docker volume ls --format "table {{.Name}}" 2>/dev/null | grep -q ghost; then
        echo "💾 Tìm thấy Ghost volumes:"
        docker volume ls --format "table {{.Name}}" | grep ghost
        has_old_install=true
    fi
    
    # Kiểm tra port đang được sử dụng
    if ss -tuln | grep -q ":2368\|:8080"; then
        echo "🔌 Port 2368/8080 đang được sử dụng:"
        ss -tuln | grep ":2368\|:8080"
        has_old_install=true
    fi
    
    if [ "$has_old_install" = true ]; then
        echo ""
        echo "⚠️  PHÁT HIỆN CÀI ĐẶT CŨ!"
        echo ""
        echo "Tùy chọn:"
        echo "1) Tiếp tục (có thể gây conflict)"
        echo "2) Cài đè (xóa tất cả và cài mới)"
        echo "3) Backup + Cài đè"
        echo "4) Xem thông tin cài đặt hiện tại"
        echo "5) Hủy"
        echo ""
        read -p "Chọn (1/2/3/4/5): " choice
        
        case $choice in
            1)
                echo "⏩ Tiếp tục với cài đặt cũ..."
                ;;
            2)
                cleanup_old_installation false
                ;;
            3)
                cleanup_old_installation true
                ;;
            4)
                show_current_info
                check_existing_installation  # Hỏi lại
                ;;
            5)
                echo "❌ Hủy cài đặt!"
                exit 0
                ;;
            *)
                echo "❌ Lựa chọn không hợp lệ!"
                exit 1
                ;;
        esac
    else
        echo "✅ Không tìm thấy cài đặt cũ"
    fi
}

# Dọn dẹp cài đặt cũ
cleanup_old_installation() {
    local do_backup=$1
    
    echo ""
    echo "🧹 DỌNG DẸP CÀI ĐẶT CŨ..."
    
    # Backup nếu được yêu cầu
    if [ "$do_backup" = true ]; then
        echo "💾 Tạo backup..."
        local backup_dir="$HOME/ghost-backup-$(date +%Y%m%d_%H%M%S)"
        
        if [ -d "$HOME/ghost" ]; then
            cp -r "$HOME/ghost" "$backup_dir"
            echo "✅ Backup config: $backup_dir"
        fi
        
        # Backup volumes
        if docker volume ls | grep -q ghost_content; then
            docker run --rm -v ghost_content:/data -v "$backup_dir":/backup alpine tar czf /backup/ghost_content.tar.gz -C /data .
            echo "✅ Backup content: $backup_dir/ghost_content.tar.gz"
        fi
    fi
    
    # Dừng và xóa containers
    echo "🛑 Dừng Ghost containers..."
    docker ps -q --filter "name=ghost" | xargs -r docker stop
    docker ps -aq --filter "name=ghost" | xargs -r docker rm
    
    # Xóa containers với tên chứa ghost hoặc db
    docker ps -aq --filter "name=db" | xargs -r docker rm -f
    
    # Xóa volumes
    echo "🗑️  Xóa Ghost volumes..."
    docker volume ls -q | grep ghost | xargs -r docker volume rm
    docker volume ls -q | grep -E "ghost_|db" | xargs -r docker volume rm
    
    # Xóa thư mục
    if [ -d "$HOME/ghost" ]; then
        echo "📁 Xóa thư mục ~/ghost..."
        rm -rf "$HOME/ghost"
    fi
    
    # Dọn dẹp images không sử dụng
    echo "🧽 Dọn dẹp Docker images..."
    docker image prune -f
    
    echo "✅ Dọn dẹp hoàn tất!"
    
    if [ "$do_backup" = true ]; then
        echo "📁 Backup được lưu tại: $backup_dir"
    fi
}

check_existing_installation

# Cài Docker nhanh
echo "2. Cài Docker..."
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Hỏi thông tin cơ bản
echo "3. Nhập thông tin:"
read -p "Nhập domain hoặc IP của bạn: " DOMAIN
read -p "Chọn port (2368/8080, mặc định 8080): " PORT
PORT=${PORT:-8080}
read -p "Dùng MySQL? (y/n, mặc định SQLite): " USE_MYSQL

# Tạo thư mục
mkdir -p ~/ghost
cd ~/ghost

# Tạo docker-compose đơn giản
if [[ $USE_MYSQL == "y" ]]; then
    echo "Tạo Ghost với MySQL..."
    read -p "Nhập mật khẩu MySQL: " MYSQL_PASS
    
    cat > docker-compose.yml << EOF
services:
  ghost:
    image: ghost:latest
    restart: always
    ports:
      - "2368:2368"
    environment:
      url: http://$DOMAIN:2368
      database__client: mysql
      database__connection__host: db
      database__connection__user: ghost
      database__connection__password: $MYSQL_PASS
      database__connection__database: ghostdb
    volumes:
      - ./content:/var/lib/ghost/content
    depends_on:
      - db

  db:
    image: mysql:8.0
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: $MYSQL_PASS
      MYSQL_DATABASE: ghostdb
      MYSQL_USER: ghost
      MYSQL_PASSWORD: $MYSQL_PASS
    volumes:
      - ./mysql:/var/lib/mysql
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
      timeout: 20s
      retries: 10
EOF
else
    echo "Tạo Ghost với SQLite..."
    cat > docker-compose.yml << EOF
version: '3.8'
services:
  ghost:
    image: ghost:latest
    restart: always
    ports:
      - "2368:2368"
    environment:
      url: http://$DOMAIN:2368
    volumes:
      - ./content:/var/lib/ghost/content
EOF
fi

# Mở cổng firewall
echo "4. Mở cổng $PORT..."
sudo ufw allow $PORT

# Khởi động Ghost
echo "5. Khởi động Ghost..."
if [[ $USE_MYSQL == "y" ]]; then
    echo "🗄️ Khởi động MySQL trước..."
    newgrp docker << END
docker compose up -d db
END
    echo "⏳ Chờ MySQL sẵn sàng (60 giây)..."
    sleep 60
    
    echo "👻 Khởi động Ghost..."
    newgrp docker << END
docker compose up -d ghost
END
else
    newgrp docker << END
docker compose up -d
END
fi

# Kiểm tra và tối ưu
echo ""
echo "6. Kiểm tra và tối ưu hệ thống..."

# Lấy IP công khai
echo "📡 Lấy IP công khai..."
PUBLIC_IP=$(curl -s --connect-timeout 10 ifconfig.me || curl -s --connect-timeout 10 ipinfo.io/ip || echo "UNKNOWN")

# URLs để test
LOCAL_URL="http://localhost:$PORT"
PUBLIC_URL="http://$PUBLIC_IP:$PORT"
DOMAIN_URL="http://$DOMAIN:$PORT"

# Function kiểm tra URL
test_url() {
    local url=$1
    local name=$2
    
    echo -n "🔍 Kiểm tra $name ($url)... "
    
    # Test HTTP response
    local response=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 --max-time 15 "$url" 2>/dev/null)
    
    if [[ "$response" == "200" ]]; then
        echo "✅ OK (HTTP $response)"
        return 0
    elif [[ "$response" == "000" ]]; then
        echo "❌ Không kết nối được"
        return 1
    else
        echo "⚠️ HTTP $response"
        return 1
    fi
}

# Function kiểm tra hệ thống
check_system() {
    echo "=== KIỂM TRA HỆ THỐNG ==="
    local errors=0
    
    # Kiểm tra Docker
    if sudo systemctl is-active --quiet docker; then
        echo "✅ Docker service đang chạy"
    else
        echo "❌ Docker service không chạy"
        ((errors++))
    fi
    
    # Kiểm tra container
    if docker ps --format "table {{.Names}}\t{{.Status}}" | grep -q ghost; then
        echo "✅ Ghost container đang chạy"
        docker ps --format "table {{.Names}}\t{{.Status}}" | grep ghost
    else
        echo "❌ Ghost container không chạy"
        ((errors++))
    fi
    
    # Kiểm tra MySQL nếu có
    if [[ $USE_MYSQL == "y" ]]; then
        if docker ps --format "table {{.Names}}\t{{.Status}}" | grep -q db; then
            echo "✅ MySQL container đang chạy"
        else
            echo "❌ MySQL container không chạy"
            ((errors++))
        fi
        
        # Test MySQL connection
        echo -n "🔍 Kiểm tra MySQL connection... "
        if docker exec -i $(docker ps -q --filter "name=db") mysqladmin ping -h localhost --silent 2>/dev/null; then
            echo "✅ OK"
        else
            echo "❌ MySQL chưa sẵn sàng"
            ((errors++))
        fi
    fi
    
    # Kiểm tra port
    if ss -tuln | grep -q ":$PORT"; then
        echo "✅ Port $PORT đã bind"
    else
        echo "❌ Port $PORT chưa bind"
        ((errors++))
    fi
    
    return $errors
}

# Chờ Ghost khởi động
echo "⏳ Chờ Ghost khởi động (30 giây)..."
sleep 30

# Kiểm tra hệ thống
check_system
SYSTEM_OK=$?

echo ""
echo "=== KIỂM TRA KẾT NỐI ==="

# Test các URL
test_url "$LOCAL_URL" "Local"
LOCAL_OK=$?

test_url "$PUBLIC_URL" "Public IP"
PUBLIC_OK=$?

# Nếu domain khác IP thì test domain
if [[ "$DOMAIN" != "$PUBLIC_IP" ]]; then
    test_url "$DOMAIN_URL" "Domain"
    DOMAIN_OK=$?
else
    DOMAIN_OK=$PUBLIC_OK
fi

# Hiển thị kết quả
echo ""
if [[ $SYSTEM_OK -eq 0 && ($LOCAL_OK -eq 0 || $PUBLIC_OK -eq 0) ]]; then
    echo "🎉 === THÀNH CÔNG! GHOST ĐÃ CHẠY === 🎉"
    echo ""
    echo "📱 TRUY CẬP TRANG WEB:"
    
    if [[ $PUBLIC_OK -eq 0 ]]; then
        echo "   🌐 Public: $PUBLIC_URL"
        echo "   ⚙️ Admin:  $PUBLIC_URL/ghost"
    fi
    
    if [[ $DOMAIN_OK -eq 0 && "$DOMAIN" != "$PUBLIC_IP" ]]; then
        echo "   🏠 Domain: $DOMAIN_URL"
        echo "   ⚙️ Admin:  $DOMAIN_URL/ghost"
    fi
    
    echo ""
    echo "✅ Tất cả hoạt động bình thường!"
    echo "👆 Nhấp vào link bên trên để truy cập Ghost!"
    
else
    echo "❌ === CÓ LỖI XẢY RA ==="
    echo ""
    echo "📋 THÔNG TIN DEBUG:"
    echo "   🖥️ IP VPS: $PUBLIC_IP"
    echo "   🌐 Domain: $DOMAIN"
    echo "   📊 System OK: $([ $SYSTEM_OK -eq 0 ] && echo 'YES' || echo 'NO')"
    echo "   🏠 Local OK: $([ $LOCAL_OK -eq 0 ] && echo 'YES' || echo 'NO')"
    echo "   🌍 Public OK: $([ $PUBLIC_OK -eq 0 ] && echo 'YES' || echo 'NO')"
    echo ""
    echo "🔧 CÁCH KHẮC PHỤC TỰ ĐỘNG:"
    echo ""
    echo "1️⃣ Lỗi MySQL - Đổi sang SQLite (đơn giản):"
    echo "   cd ~/ghost && docker compose down"
    echo "   nano docker-compose.yml  # Xóa phần db, bỏ database__ trong ghost"
    echo "   docker compose up -d"
    echo ""
    echo "2️⃣ Sửa MySQL:"
    echo "   cd ~/ghost && docker compose down"
    echo "   docker compose up -d db && sleep 60"
    echo "   docker compose up -d ghost"
    echo ""
    echo "3️⃣ Khởi động lại Ghost:"
    echo "   cd ~/ghost && docker compose restart"
    echo ""
    echo "4️⃣ Mở firewall:"
    echo "   sudo ufw allow 2368"
    echo "   sudo ufw reload"
    echo ""
    echo "4️⃣ Khởi động lại VPS:"
    echo "   sudo reboot"
    echo ""
    echo "5️⃣ Chạy Ghost đơn giản:"
    echo "   docker run -d --name ghost-backup -p 2368:2368 ghost:latest"
    echo ""
    echo "🌐 THỬ TRUY CẬP:"
    echo "   Local:  $LOCAL_URL"
    echo "   Public: $PUBLIC_URL"
    echo "   Domain: $DOMAIN_URL"
fi

echo ""
echo "📋 === LỆNH HỮU ÍCH ==="
echo "🔍 Kiểm tra:"
echo "   docker ps                           # Xem containers"
echo "   curl $PUBLIC_URL                    # Test từ terminal"
echo "   ss -tuln | grep $PORT               # Kiểm tra port"
echo ""
echo "🔧 Quản lý:"
echo "   cd ~/ghost && docker compose logs   # Xem logs"
echo "   cd ~/ghost && docker compose down   # Dừng Ghost"
echo "   cd ~/ghost && docker compose up -d  # Khởi động Ghost"
echo "   docker compose pull && docker compose up -d  # Cập nhật"
echo ""
echo "📁 Files: ~/ghost/docker-compose.yml"
echo "🆔 IP công khai: $PUBLIC_IP"
echo "🔌 Port: $PORT"
echo ""
echo "🔄 === TÙY CHỌN BỔ SUNG ==="
echo "1) Restore từ backup"
echo "2) Tạo backup ngay"
echo "3) Xem logs real-time"
echo ""
read -p "Chọn tùy chọn (Enter để bỏ qua): " extra_choice

case $extra_choice in
    1)
        restore_from_backup
        echo "🔄 Khởi động lại Ghost để áp dụng backup..."
        cd ~/ghost && docker compose restart
        ;;
    2)
        echo "💾 Tạo backup..."
        backup_dir="$HOME/ghost-backup-$(date +%Y%m%d_%H%M%S)"
        cp -r "$HOME/ghost" "$backup_dir"
        if docker volume ls | grep -q ghost_content; then
            docker run --rm -v ghost_content:/data -v "$backup_dir":/backup alpine tar czf /backup/ghost_content.tar.gz -C /data .
        fi
        echo "✅ Backup tạo tại: $backup_dir"
        ;;
    3)
        echo "📊 Xem logs (Ctrl+C để thoát)..."
        cd ~/ghost && docker compose logs -f
        ;;
    *)
        echo "⏩ Hoàn tất!"
        ;;
esac
