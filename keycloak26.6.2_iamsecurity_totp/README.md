# Tích hợp Keycloak 26.6.2 + vCenter 8.0 + AD LDAPs + OTP

> **Author:** PhD. Le Toan Thang  
> **Ngày:** 31.05.2026  
> **Môi trường:** Ubuntu 24.04 cho Keycloak, vCenter Appliance 8.0, Windows AD

## Mục lục

1. [Kiến trúc tổng quan](#1-kiến-trúc-tổng-quan)
2. [Chuẩn bị hạ tầng](#2-chuẩn-bị-hạ-tầng)
3. [Cài đặt Keycloak 26.6.2](#3-cài-đặt-keycloak-2662)
4. [Cấu hình vCenter 8 Certificate Authority (CA)](#4-cấu-hình-vcenter-8-certificate-authority-ca)
5. [Cấu hình AD LDAPs](#5-cấu-hình-ad-ldaps)
6. [Tích hợp Keycloak với AD LDAPs (User Federation)](#6-tích-hợp-keycloak-với-ad-ldaps-user-federation)
7. [Cấu hình OTP (TOTP) trong Keycloak](#7-cấu-hình-otp-totp-trong-keycloak)
8. [Tích hợp vCenter 8.0 với Keycloak (OIDC)](#8-tích-hợp-vcenter-80-với-keycloak-oidc)
9. [Kiểm tra toàn bộ luồng](#9-kiểm-tra-toàn-bộ-luồng)
10. [Khắc phục sự cố](#10-khắc-phục-sự-cố)

---

## 1. Kiến trúc tổng quan

```
┌──────────────────────────────────────────────────────────────────┐
│                          Người dùng                               │
│                   (Trình duyệt web)                                │
└──────────┬───────────────────────────────────────────┬────────────┘
           │                                           │
           ▼                                           ▼
┌──────────────────────┐                ┌──────────────────────────┐
│  vCenter 8.0         │                │  Keycloak 26.6.2         │
│  192.168.100.99      │◄── OIDC ──────►│  192.168.100.80          │
│  (Service Provider)  │                │  (Identity Provider)     │
└──────────────────────┘                └──────────┬───────────────┘
                                                    │
                                        ┌───────────┴───────────┐
                                        │   AD LDAPs             │
                                        │   192.168.100.20:636   │
                                        │   (User Federation)    │
                                        └───────────────────────┘
```

### Luồng xác thực

1. User truy cập `https://vcsa.lab.local` → vCenter redirect sang Keycloak
2. Keycloak hiển thị form login → user nhập **AD username/password**
3. Keycloak xác thực qua **LDAPs** (636) đến AD → thành công
4. Keycloak kiểm tra **OTP policy** → yêu cầu nhập **TOTP**
5. User nhập mã từ **Google Authenticator / Authy**
6. Keycloak phát hành token → redirect về vCenter
7. vCenter kiểm tra token, cấp quyền theo **group mapping**

> **Yêu cầu:** vSphere 8.0 Update 1+ hỗ trợ OIDC External IdP  
> Nếu vCenter cũ hơn, dùng **SAML** thay thế (xem Phụ lục)

---

## 2. Chuẩn bị hạ tầng

### 2.1. IP Planning

| Component | IP | Hostname | OS |
|---|---|---|---|
| Keycloak | 192.168.100.80 | keycloak.lab.local | Ubuntu 24.04 |
| vCenter | 192.168.100.99 | vcsa.lab.local | VCSA 8.0 |
| AD / DNS | 192.168.100.20 | dc.lab.local | Windows Server |

### 2.2. DNS Records

| Type | Name | Value |
|---|---|---|
| A | keycloak.lab.local | 192.168.100.80 |
| A | vcsa.lab.local | 192.168.100.99 |
| A | dc.lab.local | 192.168.100.20 |
| PTR (reverse) | 80.100.168.192.in-addr.arpa | keycloak.lab.local |
| PTR (reverse) | 99.100.168.192.in-addr.arpa | vcsa.lab.local |
| PTR (reverse) | 20.100.168.192.in-addr.arpa | dc.lab.local |

Nếu không có DNS nội bộ, thêm vào file `/etc/hosts` trên Keycloak và vCenter:

```bash
# Trên Keycloak
echo "192.168.100.20   dc.lab.local" >> /etc/hosts
echo "192.168.100.99   vcsa.lab.local" >> /etc/hosts

# Trên vCenter (qua SSH root)
echo "192.168.100.80   keycloak.lab.local" >> /etc/hosts
echo "192.168.100.20   dc.lab.local" >> /etc/hosts
```

### 2.3. Firewall Rules

| Source | Dest | Port | Protocol | Purpose |
|---|---|---|---|---|
| Keycloak | AD | 636 | TCP | LDAPs |
| Keycloak | AD | 389 | TCP | LDAP (fallback) |
| User | Keycloak | 443 | TCP | HTTPS Admin Console |
| User | vCenter | 443 | TCP | vSphere Web UI |
| vCenter | Keycloak | 443 | TCP | OIDC / SAML |
| Keycloak | Any | 53 | UDP/TCP | DNS |

```bash
# Trên Keycloak (ufw)
ufw allow 443/tcp

# Trên AD (Windows Firewall)
# Đảm bảo LDAPs (636) inbound đã mở
```

### 2.4. Yêu cầu phiên bản

- **Keycloak 26.6.2** (Java 21, MySQL 8.x)
- **vCenter 8.0 Update 1+** (cho OIDC), vCenter 8.0 base (dùng SAML)
- **Windows Server 2019+** với **AD Certificate Services** (cho LDAPs)

---

## 3. Cài đặt Keycloak 26.6.2

### 3.1. Chạy script cài đặt

```bash
# Copy file s2_setup_keycloak.sh lên server (nếu chưa có)
# Cấp quyền + chạy
chmod +x s2_setup_keycloak.sh
sudo bash s2_setup_keycloak.sh
```

### 3.2. Nhập thông số

| Prompt | Giá trị nhập |
|---|---|
| Domain URL | `keycloak.lab.local` |
| SSL Admin Email | `admin@lab.local` |
| SSL Type | `S` (self-signed cho lab) |
| Keycloak Admin User | `kcadmin` |
| Keycloak Admin Pass | `Kc@dmin2026!` |
| DB User | `keycloak_user` |
| DB Pass | `KcDb@2026!` |

### 3.3. Kiểm tra sau cài đặt

```bash
# Kiểm tra service
systemctl status keycloak
systemctl status nginx
systemctl status mysql

# Kiểm tra API
curl -s -f http://localhost:8080/realms/master && echo "OK"

# Xem log Keycloak
journalctl -u keycloak -n 50 --no-pager
```

### 3.4. Truy cập Admin Console

Mở trình duyệt: `https://keycloak.lab.local`

- **Administration Console** → đăng nhập: `kcadmin` / `Kc@dmin2026!`
- **Master Realm** → sử dụng cho quản trị
- Tạo realm riêng `vcenter-realm` → **Create Realm** → Name: `vcenter-realm`

---

## 4. Cấu hình vCenter 8 Certificate Authority (CA)

Mục tiêu: Đảm bảo Keycloak trust được vCenter certificate và ngược lại.

### 4.1. Lấy vCenter Root CA Certificate

SSH vào vCenter Appliance với user `root`:

```bash
# Kết nối SSH đến vCenter
ssh root@192.168.100.99

# Xem danh sách certificates
/usr/lib/vmware-vmca/bin/cert-cli list

# Export Root CA cert
openssl s_client -connect localhost:443 -showcerts </dev/null 2>/dev/null | \
  sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' | \
  head -n 30 > /tmp/vcenter_root_ca.pem

# Xác nhận file
openssl x509 -in /tmp/vcenter_root_ca.pem -text -noout | head -20
```

Copy cert từ vCenter về Keycloak:

```bash
# Từ máy workstation (scp) hoặc copy thủ công
scp root@192.168.100.99:/tmp/vcenter_root_ca.pem /tmp/
```

**Cách thay thế:** Truy cập `https://vcsa.lab.local` → click icon ổ khóa → **Certificate** → **Details** → **Export** → save PEM.

### 4.2. Import vCenter Root CA vào Keycloak Truststore

Keycloak sử dụng Java truststore tại:

```bash
JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
TRUSTSTORE=$JAVA_HOME/lib/security/cacerts
STOREPASS=changeit

# Import vCenter CA
keytool -importcert -keystore $TRUSTSTORE \
  -storepass $STOREPASS \
  -alias vcenter-ca \
  -file /tmp/vcenter_root_ca.pem \
  -noprompt

# Kiểm tra
keytool -list -keystore $TRUSTSTORE \
  -storepass $STOREPASS | grep vcenter-ca
```

### 4.3. (Tùy chọn) Ký certificate Keycloak bằng vCenter CA

Nếu muốn vCenter trust Keycloak certificate mặc định (không cần thêm thao tác ở bước 8):

```bash
# Trên Keycloak - tạo CSR
openssl req -new -newkey rsa:2048 -nodes \
  -keyout /etc/nginx/ssl/keycloak.lab.local.key \
  -out /tmp/keycloak.csr \
  -subj "/C=VN/ST=Hanoi/L=Hanoi/O=Lab/OU=IT/CN=keycloak.lab.local"

# Copy CSR sang vCenter
scp /tmp/keycloak.csr root@192.168.100.99:/tmp/

# Trên vCenter - sign CSR bằng VMCA
/usr/lib/vmware-vmca/bin/cert-cli sign \
  --csr /tmp/keycloak.csr \
  --cert /tmp/keycloak.crt

# Copy cert signed về Keycloak
scp root@192.168.100.99:/tmp/keycloak.crt /etc/nginx/ssl/

# Update Nginx config để dùng cert mới
# File: /etc/nginx/sites-available/keycloak.lab.local.conf
#   ssl_certificate /etc/nginx/ssl/keycloak.crt;
#   ssl_certificate_key /etc/nginx/ssl/keycloak.lab.local.key;

nginx -t && systemctl restart nginx
```

> **Lab:** Bước này không bắt buộc. Nếu bỏ qua, vCenter cần được import self-signed cert của Keycloak.

---

## 5. Cấu hình AD LDAPs

### 5.1. Chuẩn bị AD

Trên Windows Server (192.168.100.20):

```powershell
# 1. Kiểm tra LDAPs đã hoạt động
Get-ADDomainController -Filter * | Format-Table Name, LDAPPort, SSLPort

# 2. Nếu chưa có LDAPs (port 636), cài AD CS
Install-WindowsFeature -Name ADCS-Cert-Authority -IncludeManagementTools

# 3. Cấu hình AD CS (cần reboot)
#    - Role: Certificate Authority
#    - Setup Type: Enterprise CA
#    - CA Type: Root CA
#    - Validity: 10 năm

# 4. Export Root CA certificate
$cert = Get-ChildItem -Path Cert:\LocalMachine\Root |
        Where-Object { $_.Subject -like "*dc*" }
Export-Certificate -Cert $cert[0] -FilePath C:\ad-root-ca.cer
```

### 5.2. Tạo Service Account cho Keycloak

```powershell
# Tạo user
New-ADUser -Name "svc_keycloak" `
  -SamAccountName "svc_keycloak" `
  -UserPrincipalName "svc_keycloak@lab.local" `
  -Enabled $true `
  -AccountPassword (ConvertTo-SecureString "Svc@2026!" -AsPlainText -Force) `
  -PasswordNeverExpires $true `
  -Description "Service Account for Keycloak LDAPs sync"

# Kiểm tra user được tạo
Get-ADUser svc_keycloak
```

> Ghi nhớ thông tin:  
> **Bind DN:** `CN=svc_keycloak,CN=Users,DC=lab,DC=local`  
> **Password:** `Svc@2026!`  
> **Base DN:** `DC=lab,DC=local`

### 5.3. Import AD Root CA vào Keycloak Truststore

```bash
# Copy file ad-root-ca.cer từ AD về Keycloak (qua SCP hoặc USB)
scp administrator@192.168.100.20:C:/ad-root-ca.cer /tmp/

# Import vào Java truststore
keytool -importcert -keystore /usr/lib/jvm/java-21-openjdk-amd64/lib/security/cacerts \
  -storepass changeit \
  -alias ad-ca \
  -file /tmp/ad-root-ca.cer \
  -noprompt

# Kiểm tra
keytool -list -keystore /usr/lib/jvm/java-21-openjdk-amd64/lib/security/cacerts \
  -storepass changeit | grep ad-ca
```

### 5.4. Kiểm tra kết nối LDAPs từ Keycloak

```bash
# Cài ldap-utils
apt install -y ldap-utils

# Test kết nối SSL
echo | openssl s_client -connect 192.168.100.20:636 -servername dc.lab.local 2>/dev/null | head -15

# Test bind (sẽ hỏi password)
ldapsearch -H ldaps://192.168.100.20:636 \
  -D "cn=svc_keycloak,cn=Users,dc=lab,dc=local" \
  -W \
  -b "dc=lab,dc=local" \
  -s sub "(objectClass=user)" sAMAccountName mail | head -30
```

Kết quả mong đợi: danh sách users từ AD.

---

## 6. Tích hợp Keycloak với AD LDAPs (User Federation)

### 6.1. Tạo Realm

1. **Keycloak Admin Console** → `https://keycloak.lab.local`
2. Đăng nhập: `kcadmin` / `Kc@dmin2026!`
3. **Master Realm** (dropdown góc trái) → **Create Realm**
4. **Realm name:** `vcenter-realm`
5. **Enabled:** ON → **Create**

### 6.2. Thêm LDAP Provider

**User Federation** → **Add provider** → **ldap**

| Tab | Field | Value |
|---|---|---|
| **General** | Console display name | `AD LDAPs` |
| **General** | Vendor | `Active Directory` |
| **Connection** | Connection URL | `ldaps://192.168.100.20:636` |
| **Connection** | Enable StartTLS | `OFF` |
| **Connection** | Use Truststore SPI | `Always` |
| **Connection** | Connection timeout | `5000ms` |
| **Connection** | Read timeout | `5000ms` |
| **Connection** | Authentication | `simple` |
| **Connection** | Bind DN | `cn=svc_keycloak,cn=Users,dc=lab,dc=local` |
| **Connection** | Bind Credential | `Svc@2026!` |
| **LDAP Settings** | Search DN | `dc=lab,dc=local` |
| **LDAP Settings** | Search Scope | `Subtree` |
| **LDAP Settings** | Read Only | `ON` |
| **LDAP Settings** | Edit Mode | `READ_ONLY` |
| **LDAP Settings** | Sync Registrations | `ON` |
| **LDAP Settings** | Import Users | `ON` |
| **Sync Settings** | Periodic Full Sync | `ON` (86400s) |
| **Sync Settings** | Periodic Changed Users Sync | `ON` (3600s) |
| **Cache Settings** | Cache Policy | `DEFAULT` |

Sau khi nhập xong → **Save**.

### 6.3. Kiểm tra kết nối

Sau khi save, nhấn **Actions** → **Test connection** và **Test authentication**.

### 6.4. Cấu hình Mappers

**User Federation** → **AD LDAPs** → **Mappers** tab

**Add Builtin Mapper:** chọn tất cả → **Add selected**.

Kiểm tra các mapper quan trọng:

| Mapper | LDAP Attribute | User Attribute / Model |
|---|---|---|
| username | `sAMAccountName` | username |
| email | `mail` | email |
| first name | `givenName` | firstName |
| last name | `sn` | lastName |
| modify date | `whenChanged` | modifyDate |
| creation date | `whenCreated` | createdTimestamp |
| groups | `memberOf` | groups (cần chỉnh **Groups DN**) |

**Sửa mapper Groups:**
- **Groups LDAP DN:** `CN=Users,DC=lab,DC=local`
- **Membership LDAP Attribute:** `memberOf`
- **Membership Attribute Type:** `DN`
- **Membership User LDAP Attribute:** `distinguishedName`
- **Mode:** `READ_ONLY`
- **User Groups Retrieve Strategy:** `LOAD_GROUPS_BY_MEMBER_ATTRIBUTE`

### 6.5. Đồng bộ Users

**User Federation** → **AD LDAPs** → **Actions** → **Sync all users**

Kiểm tra: **Users** tab → danh sách users từ AD đã xuất hiện.

```bash
# Kiểm tra qua CLI (tùy chọn)
# Dùng token admin để gọi API
curl -s -X GET "https://keycloak.lab.local/admin/realms/vcenter-realm/users?first=0&max=10" \
  -H "Authorization: Bearer $(curl -s -X POST "https://keycloak.lab.local/realms/master/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "client_id=admin-cli" \
    -d "username=kcadmin" \
    -d "password=Kc@dmin2026!" \
    -d "grant_type=password" | jq -r '.access_token')" \
  -k | jq '.[].username'
```

---

## 7. Cấu hình OTP (TOTP) trong Keycloak

### 7.1. Cấu hình OTP Policy

**Authentication** → **Policies** → **OTP Policy**

| Parameter | Value | Ghi chú |
|---|---|---|
| OTP Type | `totp` | Time-based OTP |
| Hash Algorithm | `SHA256` | Cân bằng bảo mật/hiệu năng |
| Number of Digits | `6` | Định dạng phổ biến |
| Look-ahead Window | `1` | Cho phép OTP lệch 1 chu kỳ |
| Initial Secret | (mặc định) | |
| Counter | (mặc định) | Chỉ dùng cho HOTP |
| Period | `30` | giây |

**Save.**

### 7.2. Cấu hình Required Action OTP

**Authentication** → **Required Actions**

| Required Action | Enabled | Default Action |
|---|---|---|
| Configure OTP | ✅ ON | ❌ OFF |
| Update Profile | ✅ ON | ❌ OFF |
| Update Password | ✅ ON | ❌ OFF |

**Configure OTP:**
- **Enabled:** ON (cho phép sử dụng trong flows)
- **Default Action:** OFF (không tự động bắt buộc; sẽ bắt buộc qua group hoặc user config)

### 7.3. Tùy chọn triển khai OTP

#### Tùy chọn A: OTP bắt buộc toàn bộ Realm

**Realm Settings** → **Login** → **Require OTP** → ON

Tất cả user khi đăng nhập sẽ được yêu cầu thiết lập OTP.

#### Tùy chọn B: OTP theo từng User (khuyên dùng)

**Users** → **View all users** → chọn user → **Required User Actions**:

```
[X] Configure OTP
```

→ **Save**

User sẽ được yêu cầu thiết lập OTP ở lần đăng nhập kế tiếp.

#### Tùy chọn C: OTP theo Group vai trò

**Bước 1:** Tạo group `OTP-Required` → thêm members.

**Bước 2:** Tạo Conditional Flow:
1. **Authentication** → **Flows** → copy flow `Browser` → đặt tên `Browser with Conditional OTP`
2. Thêm execution `Condition - User Group` (CONDITIONAL) → chọn group `OTP-Required`
3. Thêm execution `OTP Form` (REQUIRED) → bên trong condition block

**Bước 3:** Bind flow cho realm:
- **Authentication** → **Bindings** → **Browser Flow** → chọn `Browser with Conditional OTP`

### 7.4. Đăng ký OTP cho User (end-user steps)

1. User đăng nhập lần đầu
2. Nếu có Required Action `Configure OTP`:
   - Màn hình hiển thị **QR Code**
   - User mở app **Google Authenticator / Authy / 2FAS** → scan QR
   - Nhập mã OTP 6 số từ app
   - Xác nhận → OTP đã kích hoạt
3. Lần đăng nhập sau: nhập **AD password** → nhập **OTP code** → vào hệ thống

### 7.5. Test OTP (qua REST API)

```bash
# Lấy token - lần đầu sẽ yêu cầu OTP setup
# (nếu user đã set OTP)
curl -s -X POST "https://keycloak.lab.local/realms/vcenter-realm/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=admin-cli" \
  -d "username=aduser@lab.local" \
  -d "password=<AD_PASSWORD>" \
  -d "grant_type=password" \
  -k

# Response sẽ yêu cầu OTP nếu chưa có trong token
# Nếu user đã set OTP, cần thêm param totp:
curl -s -X POST "https://keycloak.lab.local/realms/vcenter-realm/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=admin-cli" \
  -d "username=aduser@lab.local" \
  -d "password=<AD_PASSWORD>" \
  -d "totp=<123456>" \
  -d "grant_type=password" \
  -k | jq .
```

---

## 8. Tích hợp vCenter 8.0 với Keycloak (OIDC)

### 8.1. Tạo OIDC Client trong Keycloak

**Clients** → **Create client**

| Step | Field | Value |
|---|---|---|
| **Step 1** | Client ID | `vcsa` |
| **Step 1** | Name | `vCenter External IdP` |
| **Step 1** | Client authentication | `ON` |
| **Step 1** | Standard flow | ✅ |
| **Step 1** | Direct access grants | ✅ |
| **Step 2** | Valid redirect URIs | `https://vcsa.lab.local/*` |
| **Step 2** | Valid post logout redirect URIs | `https://vcsa.lab.local/*` |
| **Step 2** | Web origins | `https://vcsa.lab.local` |
| **Step 3** | Save |

**Credentials** tab → **Client Secret** → Copy (VD: `vcsA_secret_2026!`)

### 8.2. Lấy Keycloak OIDC Metadata Endpoints

```
https://keycloak.lab.local/realms/vcenter-realm/.well-known/openid-configuration
```

Các endpoint chính:

| Endpoint | URL |
|---|---|
| Issuer | `https://keycloak.lab.local/realms/vcenter-realm` |
| Authorization | `https://keycloak.lab.local/realms/vcenter-realm/protocol/openid-connect/auth` |
| Token | `https://keycloak.lab.local/realms/vcenter-realm/protocol/openid-connect/token` |
| JWKS | `https://keycloak.lab.local/realms/vcenter-realm/protocol/openid-connect/certs` |
| Userinfo | `https://keycloak.lab.local/realms/vcenter-realm/protocol/openid-connect/userinfo` |
| Logout | `https://keycloak.lab.local/realms/vcenter-realm/protocol/openid-connect/logout` |

### 8.3. Import Keycloak Certificate vào vCenter

Nếu dùng self-signed certificate cho Keycloak (bỏ qua bước 4.3):

```bash
# Trên Keycloak - export cert
openssl s_client -connect 127.0.0.1:443 -showcerts </dev/null 2>/dev/null | \
  sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' | \
  head -30 > /tmp/keycloak-selfsigned.crt

# Copy sang vCenter
scp /tmp/keycloak-selfsigned.crt root@192.168.100.99:/tmp/

# Trên vCenter - import vào VECS trust store
/usr/lib/vmware-vmca/bin/vecs-cli entry create \
  --store TRUSTED_ROOTS \
  --alias keycloak \
  --cert /tmp/keycloak-selfsigned.crt

# Kiểm tra
/usr/lib/vmware-vmca/bin/vecs-cli entry list --store TRUSTED_ROOTS

# Restart SSO services
service-control --stop --all
service-control --start --all
```

### 8.4. Register External IdP trên vCenter

**Cách A: Dùng script tự động**

SSH vào vCenter:

```bash
cat > /tmp/register-keycloak.sh << 'SCRIPT'
#!/bin/bash
SSO_DIR=/opt/vmware/bin

# Cấu hình OIDC
cat > /tmp/keycloak-oidc.json << 'EOF'
{
  "domain": "vsphere.local",
  "alias": "keycloak",
  "type": "oidc",
  "config": {
    "authorizationEndpoint": "https://keycloak.lab.local/realms/vcenter-realm/protocol/openid-connect/auth",
    "tokenEndpoint": "https://keycloak.lab.local/realms/vcenter-realm/protocol/openid-connect/token",
    "issuer": "https://keycloak.lab.local/realms/vcenter-realm",
    "jwksUri": "https://keycloak.lab.local/realms/vcenter-realm/protocol/openid-connect/certs",
    "userinfoEndpoint": "https://keycloak.lab.local/realms/vcenter-realm/protocol/openid-connect/userinfo",
    "clientId": "vcsa",
    "clientSecret": "vcsA_secret_2026!",
    "authenticationMethod": "CLIENT_SECRET_BASIC",
    "scopes": ["openid", "profile", "email"],
    "claimMappings": [
      {"from": "preferred_username", "to": "Subject"},
      {"from": "email", "to": "Email"},
      {"from": "name", "to": "Name"}
    ]
  }
}
EOF

# Chạy lệnh register
$SSO_DIR/sso-config.sh -register_external_idp \
  -t oidc \
  -f /tmp/keycloak-oidc.json

echo "Done. Restarting services..."
service-control --stop --all
service-control --start --all
SCRIPT

chmod +x /tmp/register-keycloak.sh
bash /tmp/register-keycloak.sh
```

**Cách B: Dùng vCenter Web UI**

1. Vào vCenter Web UI `https://vcsa.lab.local` → **Menu** → **Administration**
2. **Single Sign On** → **Configuration** → **Identity Provider** → **Add**
3. **Provider Type:** `OpenID Connect (OIDC)`
4. **Alias:** `keycloak`
5. **Issuer:** `https://keycloak.lab.local/realms/vcenter-realm`
6. **Authorization Endpoint:** `https://keycloak.lab.local/realms/vcenter-realm/protocol/openid-connect/auth`
7. **Token Endpoint:** `https://keycloak.lab.local/realms/vcenter-realm/protocol/openid-connect/token`
8. **JWKS URI:** `https://keycloak.lab.local/realms/vcenter-realm/protocol/openid-connect/certs`
9. **Client ID:** `vcsa`
10. **Client Secret:** `vcsA_secret_2026!`
11. **Scopes:** `openid profile email`
12. **Claim Mapping:**
    - **Subject:** `preferred_username`
    - **Email:** `email`
    - **Name:** `name`
13. **Save**

### 8.5. Cấu hình Role Mapping (Group → Permission)

Sau khi register IdP thành công:

1. **vCenter Administration** → **Single Sign On** → **Configuration** → **Identity Provider**
2. Chọn provider `keycloak`
3. **Group Mapping** tab → **Add**
4. Map AD groups (đồng bộ từ Keycloak) sang vCenter roles:

| AD Group (từ Keycloak) | vCenter Role | Permission Level |
|---|---|---|
| `CN=Domain Admins,CN=Users,DC=lab,DC=local` | `Administrator` | Full access |
| `CN=vcenter-admins,CN=Users,DC=lab,DC=local` | `Admin` | Quản trị hạ tầng |
| `CN=vcenter-operators,CN=Users,DC=lab,DC=local` | `Operator` | Vận hành VM |
| `CN=vcenter-viewers,CN=Users,DC=lab,DC=local` | `Viewer` | Read-only |

> **Lưu ý:** Cần tạo các group `vcenter-admins`, `vcenter-operators`, `vcenter-viewers` trong AD trước.

### 8.6. Kích hoạt External IdP làm mặc định (tùy chọn)

```bash
# Trên vCenter
/opt/vmware/bin/sso-config.sh -set_idp \
  -domain vsphere.local \
  -idp keycloak \
  -enable true
```

---

## 9. Kiểm tra toàn bộ luồng

### 9.1. Kiểm tra LDAPs sync

```bash
# Đếm số users đã sync từ AD (dùng API)
curl -s -X GET "https://keycloak.lab.local/admin/realms/vcenter-realm/users/count" \
  -H "Authorization: Bearer <admin-token>" \
  -k
```

### 9.2. Kiểm tra OTP

```bash
# 1. Login user từ AD (chưa có OTP)
#    → Keycloak yêu cầu Configure OTP → user scan QR + nhập mã

# 2. Login lần 2 (đã có OTP)
curl -s -X POST "https://keycloak.lab.local/realms/vcenter-realm/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=vcsa" \
  -d "client_secret=vcsA_secret_2026!" \
  -d "username=aduser@lab.local" \
  -d "password=<AD_PASSWORD>" \
  -d "totp=<OTP_CODE>" \
  -d "grant_type=password" \
  -k | jq .
```

Kết quả mong đợi:
```json
{
  "access_token": "eyJ...",
  "expires_in": 300,
  "refresh_token": "eyJ...",
  "token_type": "Bearer",
  "not-before-policy": 0,
  "session_state": "...",
  "scope": "openid profile email"
}
```

### 9.3. Kiểm tra vCenter login với Keycloak IdP

1. Mở trình duyệt ẩn danh → `https://vcsa.lab.local`
2. Chọn **Login with Keycloak** (hoặc tự động redirect nếu đã set default)
3. Nhập **AD username** (VD: `aduser@lab.local`) và **password**
4. Nếu OTP được yêu cầu → nhập mã OTP từ authenticator app
5. Đăng nhập thành công vào vCenter Web UI
6. Kiểm tra quyền → thử các thao tác tương ứng với role mapping

### 9.4. Kiểm tra logs

```bash
# Keycloak - theo dõi real-time
journalctl -u keycloak -f

# vCenter SSO log
ssh root@192.168.100.99
tail -f /var/log/vmware/sso/stdout.log
tail -f /var/log/vmware/sso/ssoAdminServer.log
```

---

## 10. Khắc phục sự cố

### 10.1. LDAPs connection error

```
Lỗi: Unable to connect to ldaps://192.168.100.20:636 - javax.net.ssl.SSLHandshakeException
```

**Nguyên nhân:** Truststore chưa có AD CA certificate.

**Khắc phục:**
```bash
# Import lại AD CA cert
keytool -importcert -keystore /usr/lib/jvm/java-21-openjdk-amd64/lib/security/cacerts \
  -storepass changeit -alias ad-ca -file /tmp/ad-root-ca.cer -noprompt

# Restart Keycloak
systemctl restart keycloak
```

### 10.2. OIDC redirect loop

**Nguyên nhân:** `Valid Redirect URIs` không khớp, hoặc certificate không được trust.

**Khắc phục:**
- Kiểm tra chính xác URL: `https://vcsa.lab.local/*` (bao gồm cả protocol)
- Kiểm tra certificate: vCenter đã trust Keycloak cert chưa? (bước 8.3)
- Xem log Keycloak: `journalctl -u keycloak -f`

### 10.3. OTP form không hiển thị

| Nguyên nhân | Khắc phục |
|---|---|
| `Configure OTP` Required Action chưa enabled | Authentication → Required Actions → bật |
| User chưa được gán Required Action | User → Required User Actions → Configure OTP |
| Flow sai | Authentication → Bindings → gán flow có OTP |
| Realm Require OTP tắt + không có group/condition | Bật Require OTP hoặc tạo conditional flow |

### 10.4. vCenter không nhận token OIDC

```bash
# Debug: decode token để xem claims
curl -s -X POST "https://keycloak.lab.local/realms/vcenter-realm/protocol/openid-connect/token" \
  -d "client_id=vcsa" \
  -d "client_secret=vcsA_secret_2026!" \
  -d "username=aduser@lab.local" \
  -d "password=<pass>" \
  -d "totp=<otp>" \
  -d "grant_type=password" -k | jq -r '.access_token' | cut -d '.' -f2 | base64 -d 2>/dev/null; echo
```

Kiểm tra xem `preferred_username` claim có tồn tại không. vCenter cần claim này để map Subject.

### 10.5. Khôi phục sau lỗi

```bash
# Trên vCenter - xóa IdP và dùng local SSO
/opt/vmware/bin/sso-config.sh -unregister_external_idp -t oidc -a keycloak
service-control --stop --all
service-control --start --all

# Trên Keycloak - test độc lập (bỏ qua vCenter)
curl -s "https://keycloak.lab.local/realms/vcenter-realm/.well-known/openid-configuration" -k | jq .
```

---

## Phụ lục

### A. SAML Alternative (cho vCenter < 8.0 U1)

Nếu vCenter chưa hỗ trợ OIDC:

**Trên Keycloak:**
- **Clients** → **Create** → Protocol: `saml`
- **Client ID:** `https://vcsa.lab.local/saml` (Entity ID)
- **Valid Redirect URIs:** `https://vcsa.lab.local/SAML/SSO`
- **Sign Documents:** ON
- **Sign Assertions:** ON
- **Force Name ID Format:** `username`

**Export SAML metadata:**
```
https://keycloak.lab.local/realms/vcenter-realm/protocol/saml/descriptor
```

**Trên vCenter:**
```bash
curl -k -o /tmp/keycloak-saml.xml \
  "https://keycloak.lab.local/realms/vcenter-realm/protocol/saml/descriptor"

/usr/lib/vmware-sso/vmware-sts/scripts/sso-config.sh \
  -register_external_idp -t saml \
  -f /tmp/keycloak-saml.xml

service-control --stop --all
service-control --start --all
```

### B. Cấu hình OTP Backup Codes

Keycloak hỗ trợ backup codes cho OTP. User có thể tải về danh sách mã dự phòng khi mất thiết bị.

**Authentication** → **Required Actions** → `Configure OTP` → **Backup codes:** ✅ ON

### C. Tham khảo

- Keycloak LDAP: https://www.keycloak.org/docs/latest/server_admin/#_ldap
- Keycloak OTP: https://www.keycloak.org/docs/latest/server_admin/#_otp-policy
- vCenter External IdP: https://docs.vmware.com/en/VMware-vSphere/8.0/vsphere-security/GUID-external-identity-provider.html
- Keycloak SAML: https://www.keycloak.org/docs/latest/server_admin/#saml-clients
