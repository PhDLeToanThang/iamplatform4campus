#!/bin/bash

# --- Cảnh báo và kiểm tra quyền ---
echo "======================================================"
echo "     Nâng cấp Keycloak 24.0.4 lên 26.6.2             "
echo "Author: PhD. Le Toan Thang, AI Assistant Private Local"
echo " version 31.05.2026                                   "
echo "======================================================"
echo "Script này sẽ nâng cấp Keycloak từ 24.0.4 lên 26.6.2."
echo "Hãy đảm bảo bạn đã sao lưu dữ liệu quan trọng!        "
echo "------------------------------------------------------"

if [ "$EUID" -ne 0 ]; then
    echo "Lỗi: Script này phải được chạy với quyền root. Vui lòng sử dụng 'sudo bash s2_upgrade_keycloak.sh'"
    exit 1
fi

set -e

OLD_DIR="/opt/keycloak"
BACKUP_DIR="/opt/keycloak_backup_$(date +%Y%m%d_%H%M%S)"
NEW_VERSION="26.6.2"
NEW_ZIP="keycloak-${NEW_VERSION}.zip"
NEW_URL="https://github.com/keycloak/keycloak/releases/download/${NEW_VERSION}/${NEW_ZIP}"

echo ""
echo "--- Bước 1: Kiểm tra cài đặt hiện tại ---"
if [ ! -d "$OLD_DIR" ]; then
    echo "Lỗi: Không tìm thấy Keycloak tại $OLD_DIR."
    echo "Hãy dùng script s2_setup_keycloak.sh để cài mới."
    exit 1
fi

# Kiểm tra version hiện tại
if [ -f "$OLD_DIR/bin/kc.sh" ]; then
    CURRENT_VER=$("$OLD_DIR/bin/kc.sh" --version 2>/dev/null || echo "unknown")
    echo "Phiên bản hiện tại: $CURRENT_VER"
fi

echo ""
echo "--- Bước 2: Sao lưu Keycloak hiện tại ---"
echo "Sao lưu vào: $BACKUP_DIR"
cp -r "$OLD_DIR" "$BACKUP_DIR"
echo "Đã sao lưu thành công."

echo ""
echo "--- Bước 3: Sao lưu Database (khuyên dùng) ---"
echo "Tạo bản sao database keycloak_db..."
mysqldump -u root keycloak_db > "${BACKUP_DIR}/keycloak_db_backup.sql" 2>/dev/null && echo "Đã sao lưu database vào ${BACKUP_DIR}/keycloak_db_backup.sql" || echo "Cảnh báo: Không thể sao lưu database tự động. Hãy sao lưu thủ công."

echo ""
echo "--- Bước 4: Dừng Keycloak service ---"
systemctl stop keycloak 2>/dev/null && echo "Đã dừng keycloak service." || echo "Keycloak service không đang chạy."

echo ""
echo "--- Bước 5: Tải Keycloak ${NEW_VERSION} ---"
cd /opt
if [ -f "$NEW_ZIP" ]; then
    rm -f "$NEW_ZIP"
fi
wget "$NEW_URL" -O "$NEW_ZIP"
echo "Đã tải xuống Keycloak ${NEW_VERSION}."

echo ""
echo "--- Bước 6: Giải nén và thay thế ---"
unzip -o "$NEW_ZIP"
rm -rf "$OLD_DIR"
mv "keycloak-${NEW_VERSION}" "$OLD_DIR"

echo ""
echo "--- Bước 7: Sao chép dữ liệu từ bản cũ ---"
# Sao chép providers (JDBC driver, custom providers...)
if [ -d "$BACKUP_DIR/providers" ] && [ "$(ls -A $BACKUP_DIR/providers 2>/dev/null)" ]; then
    cp -r "$BACKUP_DIR/providers/"* "$OLD_DIR/providers/" 2>/dev/null
    echo "Đã sao chép providers từ bản cũ."
fi

# Sao chép themes tùy chỉnh
if [ -d "$BACKUP_DIR/themes" ]; then
    for theme in "$BACKUP_DIR/themes/"*/; do
        theme_name=$(basename "$theme")
        if [ "$theme_name" != "keycloak" ] && [ "$theme_name" != "base" ] && [ -d "$theme" ]; then
            cp -r "$theme" "$OLD_DIR/themes/"
            echo "Đã sao chép theme tùy chỉnh: $theme_name"
        fi
    done
fi

echo ""
echo "--- Bước 8: Phân quyền ---"
id -u keycloak &>/dev/null || useradd -r -s /bin/false keycloak
chown -R keycloak:keycloak "$OLD_DIR"
chmod -R 755 "$OLD_DIR"

echo ""
echo "--- Bước 9: Build Keycloak với driver MySQL ---"
cd "$OLD_DIR"
bin/kc.sh build --db=mysql
echo "Build hoàn tất."

echo ""
echo "--- Bước 10: Khởi động Keycloak ---"
systemctl daemon-reload
systemctl start keycloak
echo "Keycloak service đã được khởi động."

echo ""
echo "--- Bước 11: Đợi Keycloak khởi động và kiểm tra ---"
echo "Đang đợi Keycloak khởi động (tối đa 5 phút)..."
timeout 300 bash -c 'until curl -s -f http://localhost:8080/realms/master; do sleep 5; done'
if [ $? -eq 0 ]; then
    echo "✓ Keycloak đã khởi động thành công."
else
    echo "✗ Cảnh báo: Keycloak không khởi động trong vòng 5 phút."
    echo "Kiểm tra log: journalctl -u keycloak -f"
fi

echo ""
echo "======================================================"
echo "    Nâng cấp Keycloak lên ${NEW_VERSION} hoàn tất!    "
echo "======================================================"
echo "Nếu có lỗi xảy ra, bạn có thể khôi phục bằng lệnh:"
echo "  systemctl stop keycloak"
echo "  rm -rf /opt/keycloak"
echo "  cp -r ${BACKUP_DIR} /opt/keycloak"
echo "  systemctl start keycloak"
echo ""
echo "Sao lưu cũ tại: ${BACKUP_DIR}"
echo "Sao lưu database tại: ${BACKUP_DIR}/keycloak_db_backup.sql (nếu có)"
echo "======================================================"
