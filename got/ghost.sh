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

echo "=== HOÀN THÀNH ==="
echo "🎉 Ghost đã chạy tại: http://$DOMAIN:2368"
echo "⚙️ Admin: http://$DOMAIN:2368/ghost"
echo ""
echo "Lệnh hữu ích:"
echo "- Xem logs: cd ~/ghost && docker compose logs -f"
echo "- Dừng: cd ~/ghost && docker compose down"
echo "- Khởi động: cd ~/ghost && docker compose up -d"
echo ""
echo "📁 File trong: ~/ghost/"
echo ""
echo "Nếu không truy cập được, thử:"
echo "sudo reboot"
