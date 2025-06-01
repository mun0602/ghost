#!/bin/bash

# Script cài Ghost đơn giản
echo "=== GHOST CÀI ĐẶT ĐƠN GIẢN ==="

# Cập nhật package list
echo "1. Cập nhật package list..."
sudo apt update
sudo apt install -y curl wget net-tools iproute2

# Cài Docker nhanh
echo "2. Cài Docker..."
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Hỏi thông tin cơ bản
echo "3. Nhập thông tin:"
read -p "Nhập domain hoặc IP của bạn: " DOMAIN
read -p "Dùng MySQL? (y/n, mặc định SQLite): " USE_MYSQL

# Tạo thư mục
mkdir -p ~/ghost
cd ~/ghost

# Tạo docker-compose đơn giản
if [[ $USE_MYSQL == "y" ]]; then
    echo "Tạo Ghost với MySQL..."
    read -p "Nhập mật khẩu MySQL: " MYSQL_PASS
    
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
echo "4. Mở cổng 2368..."
sudo ufw allow 2368

# Khởi động Ghost
echo "5. Khởi động Ghost..."
newgrp docker << END
docker compose up -d
END

# Kiểm tra và tối ưu
echo ""
echo "6. Kiểm tra và tối ưu hệ thống..."

# Lấy IP công khai
echo "📡 Lấy IP công khai..."
PUBLIC_IP=$(curl -s --connect-timeout 10 ifconfig.me || curl -s --connect-timeout 10 ipinfo.io/ip || echo "UNKNOWN")

# URLs để test
LOCAL_URL="http://localhost:2368"
PUBLIC_URL="http://$PUBLIC_IP:2368"
DOMAIN_URL="http://$DOMAIN:2368"

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
    
    # Kiểm tra port
    if ss -tuln | grep -q ":2368"; then
        echo "✅ Port 2368 đã bind"
    else
        echo "❌ Port 2368 chưa bind"
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
    echo "1️⃣ Khởi động lại Ghost:"
    echo "   cd ~/ghost && docker compose restart"
    echo ""
    echo "2️⃣ Mở firewall:"
    echo "   sudo ufw allow 2368"
    echo "   sudo ufw reload"
    echo ""
    echo "3️⃣ Xem logs lỗi:"
    echo "   cd ~/ghost && docker compose logs --tail 50"
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
echo "   ss -tuln | grep 2368                # Kiểm tra port"
echo ""
echo "🔧 Quản lý:"
echo "   cd ~/ghost && docker compose logs   # Xem logs"
echo "   cd ~/ghost && docker compose down   # Dừng Ghost"
echo "   cd ~/ghost && docker compose up -d  # Khởi động Ghost"
echo "   docker compose pull && docker compose up -d  # Cập nhật"
echo ""
echo "📁 Files: ~/ghost/docker-compose.yml"
echo "🆔 IP công khai: $PUBLIC_IP"
