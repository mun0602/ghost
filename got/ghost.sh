#!/bin/bash

# Script cài Ghost đơn giản
echo "=== GHOST CÀI ĐẶT ĐƠN GIẢN ==="

# Cập nhật package list
echo "1. Cập nhật package list..."
sudo apt update

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

# Kiểm tra và khắc phục
echo ""
echo "6. Kiểm tra hệ thống..."
sleep 10

# Function kiểm tra
check_ghost() {
    echo "=== KIỂM TRA HỆ THỐNG ==="
    
    # Kiểm tra Docker đang chạy
    if ! sudo systemctl is-active --quiet docker; then
        echo "❌ Docker chưa chạy"
        echo "🔧 Khắc phục: sudo systemctl start docker"
        return 1
    else
        echo "✅ Docker đang chạy"
    fi
    
    # Kiểm tra container Ghost
    if docker ps | grep -q ghost; then
        echo "✅ Ghost container đang chạy"
    else
        echo "❌ Ghost container không chạy"
        echo "🔧 Xem lỗi: cd ~/ghost && docker compose logs"
        return 1
    fi
    
    # Kiểm tra port 2368
    if netstat -tuln | grep -q ":2368"; then
        echo "✅ Port 2368 đang mở"
    else
        echo "❌ Port 2368 không mở"
        echo "🔧 Khắc phục: cd ~/ghost && docker compose restart"
        return 1
    fi
    
    # Kiểm tra firewall
    if sudo ufw status | grep -q "2368"; then
        echo "✅ Firewall đã cho phép port 2368"
    else
        echo "⚠️ Firewall chưa mở port 2368"
        echo "🔧 Khắc phục: sudo ufw allow 2368"
        sudo ufw allow 2368
    fi
    
    # Test kết nối
    echo ""
    echo "📡 Kiểm tra kết nối..."
    if curl -s --connect-timeout 5 http://localhost:2368 >/dev/null; then
        echo "✅ Ghost phản hồi tại localhost"
        echo "🎉 THÀNH CÔNG! Truy cập: http://$DOMAIN:2368"
        return 0
    else
        echo "❌ Ghost không phản hồi"
        return 1
    fi
}

# Chạy kiểm tra
if check_ghost; then
    echo ""
    echo "=== HOÀN THÀNH THÀNH CÔNG ==="
    echo "🎉 Ghost đã chạy tại: http://$DOMAIN:2368"
    echo "⚙️ Admin: http://$DOMAIN:2368/ghost"
else
    echo ""
    echo "=== CÓ LỖI XẢY RA ==="
    echo "🔧 CÁCH KHẮC PHỤC:"
    echo ""
    echo "1. Khởi động lại Docker:"
    echo "   sudo systemctl restart docker"
    echo "   cd ~/ghost && docker compose down && docker compose up -d"
    echo ""
    echo "2. Kiểm tra logs lỗi:"
    echo "   cd ~/ghost && docker compose logs -f"
    echo ""
    echo "3. Khởi động lại VPS:"
    echo "   sudo reboot"
    echo ""
    echo "4. Chạy Ghost manual:"
    echo "   docker run -d --name ghost-manual -p 2368:2368 ghost:latest"
    echo ""
    echo "5. Kiểm tra IP công khai:"
    echo "   curl ifconfig.me"
    echo "   Thử truy cập: http://IP_CONG_KHAI:2368"
    echo ""
    echo "6. Tắt firewall tạm thời (test):"
    echo "   sudo ufw disable"
    echo ""
    echo "7. Kiểm tra port từ bên ngoài:"
    echo "   Vào https://www.yougetsignal.com/tools/open-ports/"
    echo "   Nhập IP và port 2368"
fi

echo ""
echo "📋 LỆNH HỮU ÍCH:"
echo "- Xem logs: cd ~/ghost && docker compose logs -f"
echo "- Dừng: cd ~/ghost && docker compose down"
echo "- Khởi động: cd ~/ghost && docker compose up -d"
echo "- Kiểm tra container: docker ps"
echo "- Kiểm tra port: netstat -tuln | grep 2368"
echo "- Xem IP công khai: curl ifconfig.me"
echo ""
echo "📁 File config: ~/ghost/docker-compose.yml"
