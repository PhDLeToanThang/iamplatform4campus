# Hướng dẫn tích hợp Keycloak 26.6.2 + vCenter 8.0 + AD LDAPs + OTP

## Kiến trúc tổng quan

```
┌────────────────────────────────────────────────────────────────────┐
│                          Người dùng                                │
│                   (Trình duyệt web)                                │
└──────────┬───────────────────────────────────────────┬─────────────┘
           │                                           │
           ▼                                           ▼
┌─────────────────────┐                  ┌──────────────────────────┐
│   vCenter 8.0       │                  │  Keycloak 26.6.2         │
│   192.168.100.99    │◄── OIDC/SAML ───►│  192.168.100.80          │
│   (Service Provider)│                  │  (Identity Provider)     │
└─────────────────────┘                  └──────────┬───────────────┘
                                                    │
                                        ┌───────────┴───────────┐
                                        │   AD LDAPs            │
                                        │   192.168.100.20      │
                                        │   (User Federation)   │
                                        └───────────────────────┘
```

## Luồng xác thực

1. User truy cập vCenter Web UI → được redirect đến Keycloak
2. Keycloak hiển thị form login → user nhập AD credentials
3. Keycloak xác thực qua LDAPs tới AD (636) → thành công
4. Keycloak yêu cầu OTP (TOTP) → user nhập mã từ app authenticator
5. Keycloak kiểm tra OTP → thành công
6. Keycloak phát hành token → redirect về vCenter
7. vCenter nhận token, cấp quyền truy cập dựa trên组成员/thuộc tính

---

## Bước 1: Chuẩn bị hạ tầng

### 1.1. DNS (khuyên dùng)
Thêm bản ghi A trên DNS server nội bộ (hoặc file `/etc/hosts` trên Keycloak và `/etc/hosts` trên vCenter):

```
192.168.100.80   keycloak.lab.local
192.168.100.99   vcsa.lab.local
192.168.100.20   dc.lab.local
```

### 1.2. Port cần mở (trên firewall)

| Component | Inbound Ports |
|---|---|
| Keycloak | 443 (HTTPS), 8080 (HTTP internal) |
| AD | 636 (LDAPs), 389 (LDAP fallback) |
| vCenter | 443 (HTTPS), 7444 (OIDC) |

---

## Bước 2: Cài đặt Keycloak 26.6.2

```bash
# Chạy script cài đặt
sudo bash s2_setup_keycloak.sh

# Nhập các tham số:
#   Domain: keycloak.lab.local
#   Email: admin@lab.local
#   SSL: S (self-signed - dùng cho lab)
#   Admin user: kcadmin
#   Admin pass: <your-password>
#   DB user: keycloak_user
#   DB pass: <your-db-password>
```

**Kiểm tra sau cài đặt:**
```bash
curl -s -f http://localhost:8080/realms/master
systemctl status keycloak
journalctl -u keycloak -n 50 --no-pager
```

Truy cập: `https://keycloak.lab.local` → Admin Console → đăng nhập với `kcadmin`.

---

## Bước 3: Cấu hình vCenter 8 Certificate Authority (CA)

Để Keycloak, vCenter và AD tin tưởng lẫn nhau qua SSL, cần thiết lập CA.

### 3.1. Lấy vCenter Root CA

SSH vào vCenter Appliance (root@192.168.100.99):

```bash
# Trên vCenter
/usr/lib/vmware-vmca/bin/cert-cli list
# Lấy root CA cert
openssl s_client -connect localhost:443 -showcerts </dev/null 2>/dev/null | openssl x509 -outform PEM > /tmp/vcenter_root_ca.pem
```

Hoặc download từ browser: `https://vcsa.lab.local` → certificate icon → export root CA.

### 3.2. Import vCenter CA vào Keycloak truststore

```bash
# Trên Keycloak
scp root@192.168.100.99:/tmp/vcenter_root_ca.pem /tmp/
# Hoặc copy thủ công

# Import vào Java truststore (dùng cho Keycloak)
keytool -importcert -keystore /usr/lib/jvm/java-21-openjdk-amd64/lib/security/cacerts \
  -storepass changeit -alias vcenter-ca -file /tmp/vcenter_root_ca.pem -noprompt

# Kiểm tra
keytool -list -keystore /usr/lib/jvm/java-21-openjdk-amd64/lib/security/cacerts \
  -storepass changeit | grep vcenter-ca
```

### 3.3. Cấu hình Keycloak HTTPS với cert do vCenter CA ký (tùy chọn)

```bash
# Tạo CSR trên Keycloak
openssl req -new -newkey rsa:2048 -nodes -keyout /etc/nginx/ssl/keycloak.lab.local.key \
  -out /tmp/keycloak.csr \
  -subj "/C=VN/ST=Hanoi/L=Hanoi/O=Lab/CN=keycloak.lab.local"

# Copy CSR sang vCenter, sign bằng VMCA
# Trên vCenter:
# /usr/lib/vmware-vmca/bin/cert-cli sign -k /tmp/keycloak.csr -o /tmp/keycloak.crt

# Copy cert signed về Keycloak và update Nginx config
```

> **Lưu ý cho lab:** Có thể bỏ qua bước 3.3 nếu dùng self-signed cert. vCenter sẽ cần được cấu hình trust self-signed cert của Keycloak (bước 7.5).

---

## Bước 4: Cấu hình AD LDAPs

### 4.1. Lấy AD Root CA (nếu AD có CA riêng)

```bash
# Trên Windows AD, export CA cert:
#   MMC → Certificates → Trusted Root Certification Authorities → Export .cer

# Copy sang Keycloak
# Import vào Java truststore
keytool -importcert -keystore /usr/lib/jvm/java-21-openjdk-amd64/lib/security/cacerts \
  -storepass changeit -alias ad-ca -file /tmp/ad_root_ca.cer -noprompt
```

### 4.2. Kiểm tra kết nối LDAPs từ Keycloak

```bash
# Cài openldap utils (nếu chưa có)
apt install -y ldap-utils

# Test LDAPs
openssl s_client -connect 192.168.100.20:636 -showcerts </dev/null 2>/dev/null | head -20

# Test bind
ldapsearch -H ldaps://192.168.100.20 -D "cn=Administrator,cn=Users,dc=lab,dc=local" -W -b "dc=lab,dc=local" -s base
```

### 4.3. Tạo service account trong AD (dùng cho Keycloak)

Trên AD, tạo user `svc_keycloak` với password bền, gán vào nhóm `Domain Users`, cấp quyền đọc toàn bộ OU cần đồng bộ.

---

## Bước 5: Tích hợp Keycloak với AD LDAPs

### 5.1. Vào Keycloak Admin Console

`https://keycloak.lab.local` → Admin Console → `kcadmin`.

### 5.2. Tạo Realm cho vCenter

- **User Federation** → **Add LDAP provider**
  - **Console** → **Master** (hoặc tạo realm mới, VD: `vcenter-realm`)
  - Tốt nhất: tạo realm riêng → **Add Realm** → Name: `vcenter-realm`

### 5.3. Cấu hình User Federation - LDAP

**User Federation** → **Add provider** → **ldap**

| Parameter | Value |
|---|---|
| **Console display name** | AD LDAPs |
| **Vendor** | Active Directory |
| **Connection URL** | `ldaps://192.168.100.20:636` |
| **Enable StartTLS** | OFF |
| **Use Truststore SPI** | `Always` |
| **Connection timeout** | `5000ms` |
| **Read timeout** | `5000ms` |
| **Authentication** | `simple` |
| **Bind DN** | `cn=svc_keycloak,cn=Users,dc=lab,dc=local` |
| **Bind Credential** | `<password>` |
| **Search DN** | `dc=lab,dc=local` |
| **Search Scope** | `Subtree` |
| **Edit Mode** | `READ_ONLY` |
| **Sync Registrations** | ON |
| **Import Users** | ON |
| **Periodic Full Sync** | ON (86400s - daily) |
| **Periodic Changed Users Sync** | ON (3600s) |

**Custom User Search Filter** (nếu cần): `(|(objectClass=user)(objectClass=person))`

### 5.4. Cấu hình Mapper cho LDAP

**Mappers** tab → **Add Builtin Mapper** → chọn tất cả → **Add selected**.

Check quan trọng:
- **username** → LDAP Attribute: `sAMAccountName`
- **email** → LDAP Attribute: `mail`
- **first name** → LDAP Attribute: `givenName`
- **last name** → LDAP Attribute: `sn`
- **groups** → check **LDAP Groups DN**: `cn=Users,dc=lab,dc=local`
- **role list** → nếu cần mapping role

### 5.5. Kiểm tra đồng bộ

**User Federation** → **AD LDAPs** → **Actions** → **Sync all users**.

Kiểm tra **Users** tab → đã thấy users từ AD.

---

## Bước 6: Cấu hình OTP (TOTP) trong Keycloak

### 6.1. Tạo Authentication Flow với OTP

**Authentication** → **Flows** → **Copy** flow `Browser` → đặt tên `Browser with OTP`

Cấu trúc flow:
```
Browser with OTP
├── Cookie (ALTERNATIVE)
├── OTP Form (REQUIRED)  ← <-- thêm OTP sau LDAP forms
└── Browser - Conditional OTP (CONDITIONAL)
    ├── Condition - User Role (REQUIRED)
    └── OTP Form (REQUIRED)
```

Cách đơn giản hơn: dùng **Required Action** OTP.

### 6.2. Cấu hình Required Action OTP cho Realm

**Realm Settings** → **Login** tab:
- **Require OTP** → OFF (để chúng ta kiểm soát qua policy)

**Authentication** → **Required Actions**:
- **Configure OTP** → Enabled: ON, Default Action: OFF
- **Update Profile** → như trên

### 6.3. Cấu hình OTP Policy

**Authentication** → **Policies** → **OTP Policy**:

| Parameter | Value |
|---|---|
| **OTP Type** | `totp` (Time-based) |
| **Hash Algorithm** | `SHA256` |
| **Number of Digits** | `6` |
| **Look-ahead Window** | `1` |
| **Initial Secret (shared)** | dùng mặc định |
| **Counter** | dùng mặc định |
| **Period (TOTP only)** | `30` seconds |

### 6.4. Cấu hình OTP cho từng user (hoặc group)

**Cách 1 - User bắt buộc tự đăng ký OTP lần đầu:**
- **Users** → chọn user → **Required User Actions** → **Configure OTP** → Save
- User sẽ được yêu cầu quét mã QR và nhập OTP khi đăng nhập lần đầu

**Cách 2 - Bắt buộc OTP qua Group policy:**
- **Groups** → tạo group `OTP-Required` → **Role Mappings**
- **Authentication** → **Flows** → tạo conditional flow với điều kiện role/group

**Cách 3 - Bắt buộc OTP toàn bộ realm:**
- **Realm Settings** → **Login** → Require OTP → ON

### 6.5. Test OTP flow

1. Mở tab ẩn danh → `https://keycloak.lab.local/realms/vcenter-realm/account`
2. Đăng nhập với user AD → pass AD
3. Nếu có Required Action OTP → QR code hiện ra
4. Dùng Google Authenticator / Authy / 2FAS scan QR
5. Nhập mã OTP → xác thực xong
6. Lần sau login → nhập AD pass → nhập OTP → OK

---

## Bước 7: Cấu hình vCenter 8.0 dùng Keycloak làm External IdP (OIDC)

### 7.1. Tạo Client trong Keycloak cho vCenter

**Clients** → **Create client**:

| Parameter | Value |
|---|---|
| **Client ID** | `vcsa` |
| **Name** | vCenter 8.0 |
| **Client authentication** | ON (Client Secret) |
| **Authentication flow** | ✅ Standard flow ✅ Direct access grants |
| **Root URL** | `https://vcsa.lab.local` |
| **Valid redirect URIs** | `https://vcsa.lab.local/*` |
| **Valid post logout redirect URIs** | `https://vcsa.lab.local/*` |
| **Web origins** | `https://vcsa.lab.local` |

**Credentials** tab → **Client Secret** → copy secret (dùng ở bước 7.3).

### 7.2. Export Keycloak OIDC metadata

```
https://keycloak.lab.local/realms/vcenter-realm/.well-known/openid-configuration
```

Nội dung dạng JSON có chứa các endpoint:
- `issuer`
- `authorization_endpoint`
- `token_endpoint`
- `jwks_uri`
- `userinfo_endpoint`

### 7.3. Cấu hình External IdP trên vCenter

SSH vào vCenter (root):

```bash
# Kích hoạt External Identity Provider API
cmsso-util domain-deploy --activate-external-idp

# Tạo file JSON cấu hình IdP
cat > /tmp/keycloak-idp.json << 'EOF'
{
  "domain": "vsphere.local",
  "alias": "keycloak",
  "oidc": {
    "authorizationEndpoint": "https://keycloak.lab.local/realms/vcenter-realm/protocol/openid-connect/auth",
    "tokenEndpoint": "https://keycloak.lab.local/realms/vcenter-realm/protocol/openid-connect/token",
    "issuer": "https://keycloak.lab.local/realms/vcenter-realm",
    "jwksUri": "https://keycloak.lab.local/realms/vcenter-realm/protocol/openid-connect/certs",
    "userinfoEndpoint": "https://keycloak.lab.local/realms/vcenter-realm/protocol/openid-connect/userinfo",
    "clientId": "vcsa",
    "clientSecret": "<CLIENT_SECRET_TU_BUOC_7.1>",
    "authenticationMethod": "CLIENT_SECRET_BASIC",
    "scopes": ["openid", "profile", "email"],
    "claimMappings": [
      {"from": "sub", "to": "Subject"},
      {"from": "email", "to": "Email"},
      {"from": "name", "to": "Name"}
    ]
  }
}
EOF
```

> **Chú ý:** vCenter OIDC external IdP chỉ hỗ trợ từ vSphere 8.0 Update 1 trở lên.

Nếu vCenter chưa hỗ trợ OIDC, dùng SAML:

### 7.3.b SAML Alternative (cho vCenter cũ hơn)

**Trên Keycloak:**

**Clients** → **Create client**:
| Parameter | Value |
|---|---|
| **Client ID** | `https://vcsa.lab.local/saml` (SAML Entity ID của vCenter) |
| **Client Protocol** | `saml` |
| **Client SAML Endpoint** | `https://vcsa.lab.local/SAML/SSO` |
| **Valid Redirect URIs** | `https://vcsa.lab.local/*` |
| **Base URL** | `https://vcsa.lab.local` |
| **Sign Documents** | ON |
| **Sign Assertions** | ON |
| **Force POST Binding** | ON |
| **Force Name ID Format** | `username` |

**Fine Grain SAML Endpoint Config:**
- **Assertion Consumer Service POST Binding URL**: `https://vcsa.lab.local/SAML/SSO`

**Export Keycloak SAML metadata:**
```
https://keycloak.lab.local/realms/vcenter-realm/protocol/saml/descriptor
```

### 7.4. Import Keycloak IdP metadata vào vCenter

Nếu dùng OIDC:
```bash
# Apply config
/opt/vmware/bin/sso-config.sh -register_external_idp \
  -t oidc \
  -f /tmp/keycloak-idp.json

# Restart services
service-control --restart --all
```

Nếu dùng SAML:
```bash
# Download SAML metadata từ Keycloak
curl -k -o /tmp/keycloak-saml-metadata.xml \
  "https://keycloak.lab.local/realms/vcenter-realm/protocol/saml/descriptor"

# Register với vCenter
/usr/lib/vmware-sso/vmware-sts/scripts/sso-config.sh \
  -register_external_idp \
  -t saml \
  -f /tmp/keycloak-saml-metadata.xml

# Restart
service-control --restart --all
```

### 7.5. Import Keycloak certificate vào vCenter truststore (nếu self-signed)

```bash
# Lấy cert từ Keycloak
openssl s_client -connect 192.168.100.80:443 -showcerts </dev/null 2>/dev/null | \
  openssl x509 -outform PEM -out /tmp/keycloak.crt

# Import vào VECS trust store
/opt/vmware/lib64/vmware-vmca/bin/cert-cli import \
  --cert /tmp/keycloak.crt \
  --policyname TRUSTED_ROOTS

# Hoặc dùng vecs-cli
/usr/lib/vmware-vmca/bin/vecs-cli entry create \
  --store TRUSTED_ROOTS \
  --alias keycloak \
  --cert /tmp/keycloak.crt

# Restart
service-control --restart --all
```

### 7.6. Cấu hình vCenter role mapping

1. Vào vCenter Web UI → **Menu** → **Administration**
2. **Single Sign On** → **Configuration** → **Identity Provider**
3. Chọn Keycloak IdP → **Group Mapping**
4. Map AD groups (đồng bộ qua Keycloak) với vCenter roles:
   - `AD\Domain Admins` → `Administrator`
   - `AD\vCenter-Admins` → `Admin`
   - `AD\vCenter-Viewers` → `Viewer`
   - `AD\vCenter-Operators` → `Operator`
5. **Save**

---

## Bước 8: Kiểm tra toàn bộ luồng

### 8.1. Test LDAPs auth

```bash
# Dùng user thật từ AD
curl -s -X POST "https://keycloak.lab.local/realms/vcenter-realm/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=vcsa" \
  -d "client_secret=<secret>" \
  -d "username=aduser@lab.local" \
  -d "password=<ad_password>" \
  -d "grant_type=password" \
  -k | jq .
```

Nếu OTP bắt buộc, bước trên sẽ trả về lỗi cần OTP → dùng grant type `password` + `totp`:

```bash
curl -s -X POST "https://keycloak.lab.local/realms/vcenter-realm/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=vcsa" \
  -d "client_secret=<secret>" \
  -d "username=aduser@lab.local" \
  -d "password=<ad_password>" \
  -d "totp=<123456>" \
  -d "grant_type=password" \
  -k | jq .
```

### 8.2. Test vCenter login

1. Mở trình duyệt → `https://vcsa.lab.local`
2. Chọn **Login with Keycloak** (hoặc tự động redirect)
3. Nhập AD username/password
4. Nếu lần đầu → scan QR OTP → nhập mã
5. Đăng nhập thành công vào vCenter
6. Kiểm tra permissions dựa trên group mapping

### 8.3. Kiểm tra log

```bash
# Keycloak log
journalctl -u keycloak -n 100 --no-pager

# vCenter SSO log
tail -f /var/log/vmware/sso/ssoAdminServer.log
tail -f /var/log/vmware/sso/stdout.log
```

---

## Bước 9: Khắc phục sự cố thường gặp

### Vấn đề: LDAPs connection timeout

```bash
# Kiểm tra từ Keycloak
openssl s_client -connect 192.168.100.20:636 -servername dc.lab.local
# → cần import AD CA cert vào truststore

# Test bằng ldapsearch
ldapsearch -H ldaps://192.168.100.20 -D "cn=svc_keycloak,..." -w <pass> -b "dc=lab,dc=local" "(objectClass=user)" sAMAccountName
```

### Vấn đề: OIDC redirect loop

- Kiểm tra **Valid Redirect URIs** trong Keycloak client: phải chính xác là `https://vcsa.lab.local/*` (bao gồm cả port nếu vCenter dùng non-443)
- Kiểm tra HTTPS certificate: vCenter không cho phép redirect đến non-HTTPS

### Vấn đề: vCenter không nhận token

```bash
# Xác thực token
curl -s "https://keycloak.lab.local/realms/vcenter-realm/protocol/openid-connect/userinfo" \
  -H "Authorization: Bearer <token>" -k
```

Kiểm tra claim mapping: vCenter cần claim `sub` hoặc `email` để xác định user.

### Vấn đề: OTP form không hiển thị

- **Authentication** → **Required Actions**: check **Configure OTP** đã enabled?
- **Realm Settings** → **Login**: check **Require OTP**?
- Với flow tùy chỉnh: **Authentication** → **Flows**: check `Browser with OTP` đã bind vào realm?

---

## Phụ lục: Cấu hình AD LDAPs (Windows Server)

```powershell
# Trên AD (Windows Server)
# Kiểm tra LDAPs
Get-ADDomainController -Filter * | Select-Object Name, LDAPPort, SSLPort

# Cài AD CS (Certificate Services) nếu chưa có để cấp LDAPs cert
Install-WindowsFeature -Name ADCS-Cert-Authority -IncludeManagementTools

# Export Root CA
$cert = Get-ChildItem -Path Cert:\LocalMachine\Root | Where-Object {$_.Subject -like "*<DOMAIN>*"}
Export-Certificate -Cert $cert -FilePath C:\ad-root-ca.cer
```

---

## Tài liệu tham khảo

- Keycloak LDAP/AD: https://www.keycloak.org/docs/latest/server_admin/#_ldap
- Keycloak OTP: https://www.keycloak.org/docs/latest/server_admin/#_otp-policy
- vCenter External IdP (OIDC): https://docs.vmware.com/en/VMware-vSphere/8.0/vsphere-security/GUID-1C7F9C8F-0E5E-4E5E-9E5E-1C7F9C8F0E5E.html
- vCenter SAML External IdP: https://docs.vmware.com/en/VMware-vSphere/8.0/vsphere-security/GUID-3C9F9C8F-0E5E-4E5E-9E5E-1C7F9C8F0E5E.html
