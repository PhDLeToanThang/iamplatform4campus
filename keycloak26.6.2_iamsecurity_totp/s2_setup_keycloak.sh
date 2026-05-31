#!/bin/bash

# --- Cảnh báo và kiểm tra quyền ---
echo "======================================================"
echo "         Cài đặt Keycloak trên Ubuntu 24.04           "
echo "Author: PhD. Le Toan Thang, AI Assistant Private Local"
echo " version 31.05.2026                                  "
echo " Keycloak 26.6.2 | Java 21 | MySQL Connector 9.7     "
echo "======================================================"
echo "Script này sẽ cài đặt Keycloak, MySQL, Nginx và SSL.  "
echo "issue SSL for Local and Dev not for Prod public       "
echo "Hãy đảm bảo bạn đã sao lưu dữ liệu quan trọng!        "
echo "------------------------------------------------------"

# Kiểm tra xem script có đang chạy với quyền root không
if [ "$EUID" -ne 0 ]; then
    echo "Lỗi: Script này phải được chạy với quyền root. Vui lòng sử dụng 'sudo bash <tên_file>.sh'"
    exit 1
fi

set -e # Thoát ngay lập tức nếu một lệnh không thành công

# --- Hỏi các tham số từ người dùng ---
echo ""
echo "--- Nhập thông tin cấu hình ---"
read -p "1. Nhập Domain URL cho Keycloak (ví dụ: keycloak.yourdomain.com): " DOMAIN_URL
if [ -z "$DOMAIN_URL" ]; then
    echo "Lỗi: Domain URL không được để trống."
    exit 1
fi

read -p "2. Nhập Email của người quản lý SSL (ví dụ: admin@yourdomain.com): " SSL_ADMIN_EMAIL
if [ -z "$SSL_ADMIN_EMAIL" ]; then
    echo "Lỗi: Email quản lý SSL không được để trống."
    exit 1
fi

# Lựa chọn loại SSL
echo ""
echo "--- Lựa chọn Chứng chỉ SSL ---"
echo "Bạn muốn sử dụng loại chứng chỉ SSL nào?"
echo "  [S] Tự ký OpenSSL (Thích hợp cho môi trường phát triển/local)"
echo "  [L] Let's Encrypt Certbot (Thích hợp cho domain công khai, yêu cầu DNS đã trỏ)"
read -p "Chọn loại SSL (S/L, mặc định là S): " SSL_CHOICE
SSL_CHOICE=${SSL_CHOICE:-S} # Mặc định là S (Self-signed)

# Định nghĩa đường dẫn chứng chỉ và khóa, sẽ được thiết lập sau
CERT_PATH=""
KEY_PATH=""
SSL_NOTES="" # Ghi chú về SSL ở cuối script

read -p "3. Nhập Tên người dùng Admin cho Keycloak (ví dụ: kcadmin): " KC_ADMIN_USER
if [ -z "$KC_ADMIN_USER" ]; then
    echo "Lỗi: Tên người dùng Admin Keycloak không được để trống."
    exit 1
fi
read -s -p "4. Nhập Mật khẩu Admin cho Keycloak: " KC_ADMIN_PASS
echo ""
if [ -z "$KC_ADMIN_PASS" ]; then
    echo "Lỗi: Mật khẩu Admin Keycloak không được để trống."
    exit 1
fi

read -p "5. Nhập Tên người dùng Database cho Keycloak (ví dụ: keycloak_user): " KC_DB_USER
if [ -z "$KC_DB_USER" ]; then
    echo "Lỗi: Tên người dùng Database không được để trống."
    exit 1
fi
read -s -p "6. Nhập Mật khẩu Database cho Keycloak: " KC_DB_PASSWORD
echo ""
if [ -z "$KC_DB_PASSWORD" ]; then
    echo "Lỗi: Mật khẩu Database không được để trống."
    exit 1
fi

echo ""
echo "Các thông tin đã nhập:"
echo "Domain URL: $DOMAIN_URL"
echo "SSL Admin Email: $SSL_ADMIN_EMAIL"
echo "Loại SSL: $([[ "$SSL_CHOICE" == [sS] ]] && echo "Tự ký OpenSSL" || echo "Let's Encrypt Certbot")"
echo "Keycloak Admin User: $KC_ADMIN_USER"
echo "Keycloak DB User: $KC_DB_USER"
echo "------------------------------------------------------"
read -p "Bạn có muốn tiếp tục không? (y/n): " confirm
if [[ "$confirm" != [yY] ]]; then
    echo "Hủy bỏ cài đặt."
    exit 0
fi

echo ""
echo "Bắt đầu cài đặt..."

# --- Cập nhật hệ thống và cài đặt các gói cần thiết ---
echo "1. Cập nhật hệ thống và cài đặt các gói cần thiết (Java 21, MySQL, Nginx, unzip, curl, certbot, python3-certbot-nginx)..."
apt update -y
apt upgrade -y
apt install -y openjdk-21-jdk unzip curl nginx mysql-server certbot python3-certbot-nginx

# Kiểm tra cài đặt Java
if command -v java &>/dev/null; then
    echo "Java đã được cài đặt thành công: $(java -version 2>&1 | head -n 1)"
else
    echo "Lỗi: Java không được cài đặt. Vui lòng kiểm tra lại."
    exit 1
fi

# --- Cấu hình MySQL ---
echo "2. Cấu hình MySQL: Tạo database và người dùng cho Keycloak..."
systemctl is-active --quiet mysql || systemctl start mysql

# Tạo database và người dùng
mysql -u root <<EOF
CREATE DATABASE IF NOT EXISTS keycloak_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${KC_DB_USER}'@'localhost' IDENTIFIED BY '${KC_DB_PASSWORD}';
GRANT ALL PRIVILEGES ON keycloak_db.* TO '${KC_DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF

echo "MySQL Database 'keycloak_db' và người dùng '${KC_DB_USER}' đã được tạo/cấu hình."

# --- Tải xuống và cài đặt Keycloak ---
echo "3. Tải xuống và cài đặt Keycloak..."
KEYCLOAK_VERSION="26.6.2"
KEYCLOAK_ZIP="keycloak-${KEYCLOAK_VERSION}.zip"
KEYCLOAK_URL="https://github.com/keycloak/keycloak/releases/download/${KEYCLOAK_VERSION}/${KEYCLOAK_ZIP}"
INSTALL_DIR="/opt/keycloak"

if [ -d "$INSTALL_DIR" ]; then
    echo "Thư mục Keycloak đã tồn tại, xóa để cài đặt lại..."
    rm -rf "$INSTALL_DIR"
fi

cd /opt
wget "$KEYCLOAK_URL" -O "$KEYCLOAK_ZIP"
unzip "$KEYCLOAK_ZIP"
mv "keycloak-${KEYCLOAK_VERSION}" "$INSTALL_DIR"
rm "$KEYCLOAK_ZIP"

echo "Keycloak đã được cài đặt vào $INSTALL_DIR"

# Tạo người dùng và nhóm riêng cho Keycloak
echo "4. Tạo người dùng và cấu hình quyền cho Keycloak..."
id -u keycloak &>/dev/null || useradd -r -s /bin/false keycloak
chown -R keycloak:keycloak "$INSTALL_DIR"
chmod -R 755 "$INSTALL_DIR"

# --- Tải xuống MySQL JDBC Driver ---
echo "5. Tải xuống MySQL JDBC Driver..."
MYSQL_CONNECTOR_VERSION="9.7.0"
MYSQL_CONNECTOR_URL="https://repo1.maven.org/maven2/com/mysql/mysql-connector-j/${MYSQL_CONNECTOR_VERSION}/mysql-connector-j-${MYSQL_CONNECTOR_VERSION}.jar"
JDBC_PROVIDER_DIR="$INSTALL_DIR/providers"

if [ -n "$(find ${JDBC_PROVIDER_DIR} -name 'mysql-connector-j-*.jar')" ] || [ -n "$(find ${JDBC_PROVIDER_DIR} -name 'mysql-connector-java-*.jar')" ]; then
    echo "MySQL JDBC Driver đã tồn tại, bỏ qua tải xuống."
else
    echo "Đang tải xuống MySQL JDBC Driver..."
    wget -q "$MYSQL_CONNECTOR_URL" -O "${JDBC_PROVIDER_DIR}/mysql-connector-j-${MYSQL_CONNECTOR_VERSION}.jar"
    if [ $? -ne 0 ]; then
        echo "Lỗi: Tải xuống MySQL JDBC Driver thất bại."
        exit 1
    fi
    echo "MySQL JDBC Driver đã được cài đặt thành công."
fi

# --- Cấu hình Keycloak ---
echo "6. Cấu hình và Tối ưu hóa Keycloak..."
cd "$INSTALL_DIR"

# Build Keycloak với các tùy chọn build-time hợp lệ
echo "Đang chạy 'kc.sh build' để tối ưu hóa Keycloak..."
bin/kc.sh build --db=mysql

chown -R keycloak:keycloak "$INSTALL_DIR"
echo "Keycloak đã được build và tối ưu hóa."

# --- Tạo chứng chỉ SSL ---
echo "7. Cấu hình và tạo chứng chỉ SSL cho Nginx..."
SSL_DIR_SELF_SIGNED="/etc/nginx/ssl"

# Tạo dhparam.pem
if [ ! -f "$SSL_DIR_SELF_SIGNED/dhparam.pem" ]; then
    echo "Tạo dhparam.pem (có thể mất một chút thời gian)..."
    mkdir -p "$SSL_DIR_SELF_SIGNED"
    openssl dhparam -out "$SSL_DIR_SELF_SIGNED/dhparam.pem" 2048
    if [ $? -ne 0 ]; then
        echo "Lỗi: Không thể tạo dhparam.pem."
        exit 1
    fi
fi

# Tạo thư mục web root cho Nginx
mkdir -p /var/www/html
echo "<html><body>Default page</body></html>" > /var/www/html/index.html
chown -R www-data:www-data /var/www/html

if [[ "$SSL_CHOICE" == [sS] ]]; then
    echo "Đang tạo chứng chỉ SSL tự ký bằng OpenSSL..."
    mkdir -p "$SSL_DIR_SELF_SIGNED"
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout "$SSL_DIR_SELF_SIGNED/${DOMAIN_URL}.key" \
        -out "$SSL_DIR_SELF_SIGNED/${DOMAIN_URL}.crt" \
        -subj "/C=VN/ST=Hanoi/L=Hanoi/O=ATC/OU=IT/CN=${DOMAIN_URL}/emailAddress=${SSL_ADMIN_EMAIL}"
    if [ $? -ne 0 ]; then
        echo "Lỗi: Không thể tạo chứng chỉ SSL tự ký."
        exit 1
    fi
    chmod 600 "$SSL_DIR_SELF_SIGNED/${DOMAIN_URL}.key"
    CERT_PATH="$SSL_DIR_SELF_SIGNED/${DOMAIN_URL}.crt"
    KEY_PATH="$SSL_DIR_SELF_SIGNED/${DOMAIN_URL}.key"
    echo "Chứng chỉ SSL tự ký đã được tạo và lưu tại $SSL_DIR_SELF_SIGNED."
    SSL_NOTES="Chứng chỉ SSL là tự ký. Trình duyệt của bạn sẽ hiển thị cảnh báo bảo mật. Bạn cần chấp nhận rủi ro để tiếp tục."
elif [[ "$SSL_CHOICE" == [lL] ]]; then
    echo "Đang cài đặt chứng chỉ SSL bằng Let's Encrypt Certbot..."
    # Tạo cấu hình Nginx tạm thời chỉ cho HTTP
    NGINX_TEMP_CONF="/etc/nginx/sites-available/${DOMAIN_URL}_temp.conf"
    cat <<EOF > "$NGINX_TEMP_CONF"
server {
    listen 80;
    server_name ${DOMAIN_URL};
    location / {
        root /var/www/html;
        index index.html;
    }
}
EOF
    ln -sf "$NGINX_TEMP_CONF" "/etc/nginx/sites-enabled/"
    
    # Xóa default nếu có
    if [ -f "/etc/nginx/sites-enabled/default" ]; then
        rm "/etc/nginx/sites-enabled/default"
    fi
    
    # Khởi động Nginx để áp dụng cấu hình tạm thời
    nginx -t && systemctl restart nginx
    
    # Chạy certbot để lấy chứng chỉ
    certbot --nginx -d "$DOMAIN_URL" --email "$SSL_ADMIN_EMAIL" --agree-tos --non-interactive --redirect --staple-ocsp --preferred-challenges http-01
    if [ $? -ne 0 ]; then
        echo "Lỗi: Certbot không thể lấy chứng chỉ SSL. Vui lòng kiểm tra DNS và log Certbot."
        exit 1
    fi
    
    # Lấy đường dẫn chứng chỉ
    CERT_PATH="/etc/letsencrypt/live/${DOMAIN_URL}/fullchain.pem"
    KEY_PATH="/etc/letsencrypt/live/${DOMAIN_URL}/privkey.pem"
    
    # Xóa cấu hình tạm thời
    rm -f "$NGINX_TEMP_CONF"
    rm -f "/etc/nginx/sites-enabled/${DOMAIN_URL}_temp.conf"
    
    echo "Chứng chỉ Let's Encrypt đã được cấp và cấu hình bởi Certbot."
    SSL_NOTES="Chứng chỉ SSL được cấp bởi Let's Encrypt và sẽ tự động gia hạn. Đảm bảo tên miền của bạn được phân giải đúng DNS."
else
    echo "Lựa chọn SSL không hợp lệ. Vui lòng chạy lại script."
    exit 1
fi

# --- Cấu hình Nginx làm Reverse Proxy ---
echo "8. Cấu hình Nginx làm Reverse Proxy..."
NGINX_CONF="/etc/nginx/sites-available/${DOMAIN_URL}.conf"

cat <<EOF > "$NGINX_CONF"
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN_URL};
    # Chuyển hướng tất cả HTTP sang HTTPS
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${DOMAIN_URL};

    ssl_certificate ${CERT_PATH};
    ssl_certificate_key ${KEY_PATH};
    ssl_dhparam ${SSL_DIR_SELF_SIGNED}/dhparam.pem;

    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers "EECDH+AESGCM:EDH+AESGCM:AES256+EECDH:AES256+EDH";
    
    # Tăng giới hạn kích thước body cho các request lớn
    client_max_body_size 10M;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Server \$host;
        proxy_set_header X-Forwarded-Port \$server_port;
        
        # Cấu hình timeout
        proxy_connect_timeout 300;
        proxy_send_timeout 300;
        proxy_read_timeout 300;
        send_timeout 300;
        
        # Cấu hình buffer
        proxy_buffering on;
        proxy_buffer_size 4k;
        proxy_buffers 8 4k;
        proxy_busy_buffers_size 8k;
        
        # Headers quan trọng cho Keycloak
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;
    }
}
EOF

# Tạo symlink
ln -sf "$NGINX_CONF" "/etc/nginx/sites-enabled/"

# Kiểm tra cú pháp Nginx và khởi động lại
nginx -t
if [ $? -ne 0 ]; then
    echo "Lỗi: Lỗi cú pháp trong cấu hình Nginx. Vui lòng kiểm tra file $NGINX_CONF."
    exit 1
fi
systemctl restart nginx
echo "Nginx đã được cấu hình và khởi động lại."

# --- Tạo Systemd Service cho Keycloak ---
echo "9. Tạo và cấu hình Systemd Service cho Keycloak..."
SYSTEMD_SERVICE_FILE="/etc/systemd/system/keycloak.service"

cat <<EOF > "$SYSTEMD_SERVICE_FILE"
[Unit]
Description=Keycloak Authentication Server
After=network.target mysql.service

[Service]
Type=idle
User=keycloak
Group=keycloak
ExecStart=${INSTALL_DIR}/bin/kc.sh start --optimized
LimitNOFILE=100000
TimeoutStartSec=600
Restart=on-failure
RestartSec=30

# Cấu hình runtime qua biến môi trường
Environment="KC_DB=mysql"
Environment="KC_DB_URL_HOST=localhost"
Environment="KC_DB_URL_DATABASE=keycloak_db"
Environment="KC_DB_USERNAME=${KC_DB_USER}"
Environment="KC_DB_PASSWORD=${KC_DB_PASSWORD}"
Environment="KC_HOSTNAME=${DOMAIN_URL}"
Environment="KC_PROXY=edge"
Environment="KC_HTTP_ENABLED=true"
Environment="KC_HTTP_PORT=8080"
Environment="KC_HEALTH_ENABLED=true"
Environment="KC_METRICS_ENABLED=true"
Environment="KC_LOG_LEVEL=INFO"

# Cấu hình proxy headers
Environment="KC_PROXY_HEADERS=xforwarded"

# === TỰ ĐỘNG TẠO ADMIN TRONG LẦN KHỞI ĐỘNG ĐẦU TIÊN ===
Environment="KEYCLOAK_ADMIN=${KC_ADMIN_USER}"
Environment="KEYCLOAK_ADMIN_PASSWORD=${KC_ADMIN_PASS}"

[Install]
WantedBy=multi-user.target
EOF

echo "File keycloak.service đã được tạo tại $SYSTEMD_SERVICE_FILE."

# Kích hoạt và khởi động service
systemctl daemon-reload
systemctl enable keycloak
systemctl start keycloak

echo "Keycloak Service đã được kích hoạt và đang khởi động..."

# --- Đợi Keycloak khởi động hoàn tất ---
echo "10. Đợi Keycloak khởi động hoàn tất (có thể mất vài phút)..."
timeout 300 bash -c 'until curl -s -f http://localhost:8080/realms/master; do sleep 5; done'
if [ $? -eq 0 ]; then
    echo "Keycloak đã khởi động thành công."
else
    echo "Cảnh báo: Keycloak không khởi động trong vòng 5 phút. Vui lòng kiểm tra thủ công."
fi

# --- Cấu hình tường lửa (UFW) ---
echo "11. Cấu hình tường lửa (UFW)..."
ufw allow OpenSSH
ufw allow 'Nginx Full'
ufw --force enable
echo "Tường lửa UFW đã được cấu hình."

# --- Kiểm tra kết nối giữa Nginx và Keycloak ---
echo "12. Kiểm tra kết nối giữa Nginx và Keycloak..."
sleep 10

# Kiểm tra xem Keycloak có phản hồi trực tiếp không
if curl -s -f http://localhost:8080/realms/master > /dev/null; then
    echo "✓ Keycloak đang chạy và phản hồi trực tiếp."
else
    echo "✗ Lỗi: Keycloak không phản hồi trực tiếp tại http://localhost:8080/realms/master"
    echo "Vui lòng kiểm tra log Keycloak: journalctl -u keycloak -f"
fi

# Kiểm tra xem Nginx có thể proxy đến Keycloak không
if curl -s -f -k https://${DOMAIN_URL}/realms/master > /dev/null; then
    echo "✓ Nginx đang proxy đúng đến Keycloak."
else
    echo "✗ Lỗi: Nginx không thể proxy đến Keycloak tại https://${DOMAIN_URL}/realms/master"
    echo "Vui lòng kiểm tra log Nginx: tail -f /var/log/nginx/error.log"
fi

# --- Thêm domain vào file hosts nếu cần thiết ---
echo "13. Kiểm tra và thêm domain vào file hosts nếu cần thiết..."
if ! grep -q "${DOMAIN_URL}" /etc/hosts; then
    echo "127.0.0.1 ${DOMAIN_URL}" >> /etc/hosts
    echo "Đã thêm ${DOMAIN_URL} vào file hosts."
fi

# --- Hoàn tất ---
echo "======================================================"
echo "         Cài đặt Keycloak hoàn tất!                  "
echo "======================================================"
echo "Bạn có thể truy cập Keycloak tại: https://${DOMAIN_URL}"
echo ""
echo "Thông tin Admin Keycloak:"
echo "Tên người dùng: ${KC_ADMIN_USER}"
echo "Mật khẩu: ${KC_ADMIN_PASS}"
echo ""
echo "Lưu ý quan trọng:"
echo "1. $SSL_NOTES"
echo "2. Đảm bảo rằng Domain URL của bạn đã được trỏ (DNS A record) đến địa chỉ IP của máy chủ này."
echo "3. Kiểm tra trạng thái Keycloak service bằng lệnh: sudo systemctl status keycloak"
echo "   Và Nginx service bằng lệnh: sudo systemctl status nginx"
echo "4. Nếu bạn gặp sự cố, hãy kiểm tra log Keycloak tại: journalctl -u keycloak -f"
echo "   Và log Nginx tại: tail -f /var/log/nginx/error.log"
echo "======================================================"
