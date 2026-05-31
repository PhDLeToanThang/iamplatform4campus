# Tích hợp Keycloak 26.6.2 + Power BI Report Server + AD qnet.edu.vn + OTP

> **Author:** PhD. Le Toan Thang  
> **Ngày:** 31.05.2026  
> **Môi trường:** Ubuntu 24.04 (Keycloak), Windows Server (PBIRS + AD)

## Mục lục

1. [Kiến trúc tổng quan](#1-kiến-trúc-tổng-quan)
2. [Chuẩn bị hạ tầng](#2-chuẩn-bị-hạ-tầng)
3. [Cài đặt Keycloak 26.6.2](#3-cài-đặt-keycloak-2662)
4. [Cấu hình AD qnet.edu.vn (192.168.100.27) - LDAPs](#4-cấu-hình-ad-qneteduvn-19216810027---ldaps)
5. [Tích hợp Keycloak với AD qnet.edu.vn (User Federation)](#5-tích-hợp-keycloak-với-ad-qneteduvn-user-federation)
6. [Cấu hình OTP (TOTP) trong Keycloak](#6-cấu-hình-otp-totp-trong-keycloak)
7. [Tạo Client trong Keycloak cho Power BI RS](#7-tạo-client-trong-keycloak-cho-power-bi-rs)
8. [Xây dựng Custom Security Extension cho PBIRS](#8-xây-dựng-custom-security-extension-cho-pbirs)
9. [Triển khai Custom Extension lên PBIRS](#9-triển-khai-custom-extension-lên-pbirs)
10. [Cấu hình Power BI Report Server](#10-cấu-hình-power-bi-report-server)
11. [Kiểm tra toàn bộ luồng](#11-kiểm-tra-toàn-bộ-luồng)
12. [Khắc phục sự cố](#12-khắc-phục-sự-cố)
13. [Phụ lục: Nâng cấp - Tùy biến giao diện login form](#13-phụ-lục-nâng-cấp---tùy-biến-giao-diện-login-form)

---

## 1. Kiến trúc tổng quan

```
┌───────────────────────────────────────────────────────────────────────────┐
│                            Người dùng                                     │
│                      (Trình duyệt web)                                    │
└────┬────────────────────────────────────────────┬─────────────────────────┘
     │                                            │
     ▼                                            ▼
┌──────────────────────┐              ┌─────────────────────────────────────┐
│  Power BI RS         │              │  Keycloak 26.6.2                    │
│  192.168.100.19      │◄─ OIDC ─────►│  192.168.100.80                     │
│  (Service Provider)  │   + Forms    │  (Identity Provider)                │
│                      │   Auth       │                                     │
│  PBIRS               │              │  ├── Realm: pbirs-realm             │
│  CustomSecurity.dll  │              │  ├── Client: pbirs-client           │
│  (OIDC integration)  │              │  ├── User Federation: qnet LDAPs    │
└──────────────────────┘              │  └── OTP Policy: TOTP + Backup Codes│
                                      └─────────────┬───────────────────────┘
                                                    │
                                                    ▼
                                      ┌──────────────────────────┐
                                      │  AD qnet.edu.vn          │
                                      │  192.168.100.27:636      │
                                      │  (User Federation)       │
                                      │  Users: user@qnet.edu.vn │
                                      │  Groups: QNET\*, PBIRS\* │
                                      └──────────────────────────┘
```

### Luồng xác thực chi tiết

```
Bước 1: User truy cập https://pbirs.qnet.edu.vn/reports
    ↓
Bước 2: PBIRS nhận thấy chưa có session → redirect đến
        /LogonPage.aspx?ReturnUrl=%2freports (Forms Auth mặc định)
    ↓
Bước 3: CustomSecurityExtension bắt request, redirect sang Keycloak:
        https://keycloak.lab.local/realms/pbirs-realm/protocol/openid-connect/auth?
          client_id=pbirs-client&redirect_uri=https://pbirs.qnet.edu.vn/KeycloakCallback
          &response_type=code&scope=openid+profile+email
    ↓
Bước 4: Keycloak hiển thị form đăng nhập
    ↓
Bước 5: User nhập username/password AD (qnet.edu.vn)
    ↓
Bước 6: Keycloak xác thực qua LDAPs→AD (636) → OK
    ↓
Bước 7: Keycloak kiểm tra OTP policy → yêu cầu TOTP
    ↓
Bước 8: User nhập mã OTP từ Google Authenticator / Authy
    ↓
Bước 9: Keycloak kiểm tra OTP → OK → phát hành authorization code
    ↓
Bước 10: Keycloak redirect về PBIRS callback URL:
         https://pbirs.qnet.edu.vn/KeycloakCallback?code=xxx&state=yyy
    ↓
Bước 11: CustomSecurityExtension nhận code → gọi
         POST https://keycloak/.../token → nhận access_token + id_token
    ↓
Bước 12: Extension validate token (JWKS), lấy user claims (preferred_username)
    ↓
Bước 13: Extension tạo session trong PBIRS (FormsAuthentication.SetAuthCookie)
    ↓
Bước 14: User được redirect về trang reports ban đầu
    ↓
Bước 15. PBIRS render nội dung với quyền của user
```

---

## 2. Chuẩn bị hạ tầng

### 2.1. IP Planning

| Component | IP | Hostname | OS | Ghi chú |
|---|---|---|---|---|
| Keycloak | 192.168.100.80 | keycloak.lab.local | Ubuntu 24.04 | Identity Provider |
| Power BI RS | 192.168.100.19 | pbirs.qnet.edu.vn | Windows Server 2022 | PBIRS 2022+ |
| AD / DNS | 192.168.100.27 | dc.qnet.edu.vn | Windows Server 2022 | Domain: qnet.edu.vn |

### 2.2. DNS Records

| Type | Name | Value |
|---|---|---|
| A | keycloak.lab.local | 192.168.100.80 |
| A | pbirs.qnet.edu.vn | 192.168.100.19 |
| A | dc.qnet.edu.vn | 192.168.100.27 |

> **Quan trọng:** Power BI Report Server yêu cầu hostname khớp với SSL certificate.  
> Cấu hình DNS hoặc hosts file trên tất cả các máy.

Trên Keycloak:
```bash
echo "192.168.100.27   dc.qnet.edu.vn" >> /etc/hosts
echo "192.168.100.19   pbirs.qnet.edu.vn" >> /etc/hosts
```

Trên PBIRS (Windows, PowerShell Admin):
```powershell
Add-Content -Path "$env:windir\System32\drivers\etc\hosts" -Value "192.168.100.80   keycloak.lab.local"
```

### 2.3. Firewall Rules

| Source | Dest | Port | Protocol | Purpose |
|---|---|---|---|---|
| Keycloak | AD qnet | 636 | TCP | LDAPs |
| Keycloak | AD qnet | 389 | TCP | LDAP (fallback) |
| User | Keycloak | 443 | TCP | Login UI |
| User | PBIRS | 443 | TCP | Power BI Web Portal |
| PBIRS | Keycloak | 443 | TCP | OIDC token validation |
| PBIRS | AD qnet | 389/636 | TCP | PBIRS native AD auth (nếu cần) |

### 2.4. Yêu cầu phiên bản

| Component | Version | Ghi chú |
|---|---|---|
| Keycloak | 26.6.2 | Java 21, MySQL/MariaDB |
| Power BI RS | 2022+ | Hỗ trợ Custom Security Extension |
| .NET | 4.8+ | Để build custom extension |
| AD | Windows Server 2022 | Functional level 2016+ |
| Visual Studio | 2022 Community | Hoặc dùng `csc.exe` compiler |

---

## 3. Cài đặt Keycloak 26.6.2

```bash
chmod +x s2_setup_keycloak.sh
sudo bash s2_setup_keycloak.sh
```

**Tham số:**

| Field | Value |
|---|---|
| Domain URL | `keycloak.lab.local` |
| SSL Email | `admin@qnet.edu.vn` |
| SSL Type | `S` (self-signed lab) |
| Admin User | `kcadmin` |
| Admin Pass | `Kc@dmin2026!` |
| DB User | `keycloak_user` |
| DB Pass | `KcDb@2026!` |

**Kiểm tra:**
```bash
systemctl status keycloak
curl -s -f http://localhost:8080/realms/master
```

---

## 4. Cấu hình AD qnet.edu.vn (192.168.100.27) - LDAPs

### 4.1. Kiểm tra LDAPs trên AD

```powershell
# Trên AD qnet.edu.vn (PowerShell Admin)
Get-ADDomainController -Filter * | Format-Table Name, LDAPPort, SSLPort

# Kiểm tra LDAPs port 636 đang listen
netstat -an | findstr ":636"
```

Nếu chưa có LDAPs, cài AD Certificate Services:

```powershell
Install-WindowsFeature -Name ADCS-Cert-Authority -IncludeManagementTools
# Sau đó cấu hình Enterprise Root CA qua giao diện
```

### 4.2. Lấy thông tin AD qnet.edu.vn

```powershell
# Lấy thông tin domain
Get-ADDomain | Select-Object DNSRoot, NetBIOSName, DistinguishedName

# Kết quả mẫu:
# DNSRoot: qnet.edu.vn
# NetBIOSName: QNET
# DistinguishedName: DC=qnet,DC=edu,DC=vn
```

### 4.3. Tạo Service Account cho Keycloak

```powershell
# Tạo user
New-ADUser -Name "svc_keycloak_pbirs" `
  -SamAccountName "svc_kc_pbirs" `
  -UserPrincipalName "svc_kc_pbirs@qnet.edu.vn" `
  -DisplayName "Keycloak PBIRS Service Account" `
  -Description "Service Account for Keycloak LDAP sync - Power BI RS" `
  -Enabled $true `
  -AccountPassword (ConvertTo-SecureString "SvcKc@2026!" -AsPlainText -Force) `
  -PasswordNeverExpires $true `
  -PassThru

# Add vào Domain Users (đủ quyền đọc)
Add-ADGroupMember -Identity "Domain Users" -Members "svc_kc_pbirs"

# Test đọc
Get-ADUser -Filter * -ResultSetSize 5 | Select-Object SamAccountName, UserPrincipalName
```

### 4.4. Export AD Root CA Certificate

```powershell
# Export Root CA cert (nếu AD có CA)
$cert = Get-ChildItem -Path Cert:\LocalMachine\Root |
        Where-Object { $_.Subject -like "*qnet*" -or $_.Subject -like "*dc*" }

if ($cert) {
    Export-Certificate -Cert $cert[0] -FilePath C:\qnet-ad-root-ca.cer
    Write-Host "Đã export: C:\qnet-ad-root-ca.cer"
} else {
    Write-Host "Không tìm thấy CA cert. Tự ký certificate sẽ không được trust."
    # Tạo self-signed cert tạm cho LDAPs nếu chưa có:
    # New-SelfSignedCertificate -DnsName dc.qnet.edu.vn -CertStoreLocation Cert:\LocalMachine\My
}
```

Copy file `.cer` về Keycloak:
```bash
scp administrator@192.168.100.27:C:\qnet-ad-root-ca.cer /tmp/
```

### 4.5. Import AD Root CA vào Keycloak Java Truststore

```bash
keytool -importcert -keystore /usr/lib/jvm/java-21-openjdk-amd64/lib/security/cacerts \
  -storepass changeit \
  -alias qnet-ad-ca \
  -file /tmp/qnet-ad-root-ca.cer \
  -noprompt

# Kiểm tra
keytool -list -keystore /usr/lib/jvm/java-21-openjdk-amd64/lib/security/cacerts \
  -storepass changeit | grep qnet-ad-ca
```

### 4.6. Test kết nối LDAPs từ Keycloak

```bash
apt install -y ldap-utils

# Test SSL
echo | openssl s_client -connect 192.168.100.27:636 \
  -servername dc.qnet.edu.vn 2>/dev/null | head -15

# Test bind
ldapsearch -H ldaps://192.168.100.27:636 \
  -D "cn=svc_kc_pbirs,cn=Users,dc=qnet,dc=edu,dc=vn" \
  -W \
  -b "dc=qnet,dc=edu,dc=vn" \
  -s sub "(objectClass=user)" sAMAccountName mail | head -30
```

> **Kết quả mong đợi:** Danh sách users từ qnet.edu.vn hiển thị thành công.

---

## 5. Tích hợp Keycloak với AD qnet.edu.vn (User Federation)

### 5.1. Tạo Realm

1. **Keycloak Admin Console** → `https://keycloak.lab.local`
2. Đăng nhập: `kcadmin` | `Kc@dmin2026!`
3. **Master** → **Create Realm**
4. **Realm name:** `pbirs-realm`
5. **Enabled:** ON → **Create**

### 5.2. Thêm LDAP Provider

**User Federation** → **Add provider** → **ldap**

| Tab | Field | Value |
|---|---|---|
| **General** | Console display name | `AD qnet.edu.vn` |
| **General** | Vendor | `Active Directory` |
| **Connection** | Connection URL | `ldaps://192.168.100.27:636` |
| **Connection** | Enable StartTLS | `OFF` |
| **Connection** | Use Truststore SPI | `Always` |
| **Connection** | Connection timeout | `5000ms` |
| **Connection** | Read timeout | `5000ms` |
| **Connection** | Authentication | `simple` |
| **Connection** | Bind DN | `cn=svc_kc_pbirs,cn=Users,dc=qnet,dc=edu,dc=vn` |
| **Connection** | Bind Credential | `SvcKc@2026!` |
| **LDAP** | Search DN | `dc=qnet,dc=edu,dc=vn` |
| **LDAP** | Search Scope | `Subtree` |
| **LDAP** | Read Only | `ON` |
| **LDAP** | Edit Mode | `READ_ONLY` |
| **LDAP** | Sync Registrations | `ON` |
| **LDAP** | Import Users | `ON` |
| **Sync** | Periodic Full Sync | `ON` (86400s - daily) |
| **Sync** | Periodic Changed Users Sync | `ON` (3600s) |
| **Cache** | Cache Policy | `DEFAULT` |

**Save.**

### 5.3. Cấu hình Mappers

**User Federation** → **AD qnet.edu.vn** → **Mappers**

**Add Builtin Mapper:** chọn tất cả → **Add selected**.

Kiểm tra mapper quan trọng:

| Mapper | LDAP Attribute | Mapping |
|---|---|---|
| username | `sAMAccountName` | username |
| email | `mail` | email |
| first name | `givenName` | firstName |
| last name | `sn` | lastName |
| groups | `memberOf` | groups |

**Chỉnh mapper Groups** nếu cần:
- **Groups LDAP DN:** `CN=Users,DC=qnet,DC=edu,DC=vn`
- **Membership LDAP Attribute:** `memberOf`
- **Membership Attribute Type:** `DN`
- **Mode:** `READ_ONLY`

### 5.4. Đồng bộ users

**User Federation** → **AD qnet.edu.vn** → **Actions** → **Sync all users**

Kiểm tra: **Users** → danh sách AD users đã sync.

---

## 6. Cấu hình OTP (TOTP) trong Keycloak

### 6.1. OTP Policy

**Authentication** → **Policies** → **OTP Policy**

| Field | Value |
|---|---|
| OTP Type | `totp` |
| Hash Algorithm | `SHA256` |
| Number of Digits | `6` |
| Look-ahead Window | `1` |
| Period | `30` |

### 6.2. Required Actions

**Authentication** → **Required Actions**

| Action | Enabled | Default |
|---|---|---|
| Configure OTP | ✅ ON | ❌ OFF |
| Update Profile | ✅ ON | ❌ OFF |
| Update Password | ✅ ON | ❌ OFF |

### 6.3. Gán OTP cho user Power BI

Tạo group `PBIRS-Users` trong AD để quản lý user được phép dùng PBIRS:

```powershell
# Trên AD
New-ADGroup -Name "PBIRS-Users" -GroupScope Global `
  -Description "Users allowed to access Power BI Report Server" `
  -Path "CN=Users,DC=qnet,DC=edu,DC=vn"

Add-ADGroupMember -Identity "PBIRS-Users" -Members "user1", "user2", "svc_kc_pbirs"
```

Trên Keycloak, sau sync → group `PBIRS-Users` xuất hiện.

**Users** → chọn user → **Required User Actions** → `[X] Configure OTP`

Hoặc bắt buộc OTP cho toàn realm: **Realm Settings** → **Login** → **Require OTP** → ON.

---

## 7. Tạo Client trong Keycloak cho Power BI RS

### 7.1. Tạo OIDC Client

**Clients** → **Create client**

| Step | Field | Value |
|---|---|---|
| **Step 1** | Client ID | `pbirs-client` |
| **Step 1** | Name | `Power BI Report Server` |
| **Step 1** | Client authentication | `ON` |
| **Step 1** | Standard flow | ✅ |
| **Step 1** | Direct access grants | ✅ |
| **Step 2** | Valid redirect URIs | `https://pbirs.qnet.edu.vn/KeycloakCallback` |
| **Step 2** | Valid post logout redirect URIs | `https://pbirs.qnet.edu.vn/reports` |
| **Step 2** | Web origins | `https://pbirs.qnet.edu.vn` |
| **Step 3** | Save |

### 7.2. Lấy Client Secret

**Credentials** tab → **Client Secret** → Copy (VD: `pbirs_secret_2026!`)

### 7.3. Cấu hình Mapper cho Token

**Clients** → **pbirs-client** → **Client scopes** → **pbirs-client-dedicated** → **Add mapper**

**Add predefined mapper → Username:**
- **User Attribute:** `username` / `sAMAccountName`

**Add predefined mapper → Email:**
- **User Attribute:** `email`

**Add mapper → By Configuration:**

| Field | Value |
|---|---|
| Mapper Type | `User Session Note` |
| Name | `preferred_username` |
| User Session Note | `username` |
| Token Claim Name | `preferred_username` |
| Claim JSON Type | `String` |
| Add to ID token | ✅ |
| Add to access token | ✅ |
| Add to userinfo | ✅ |

### 7.4. Ghi nhớ các endpoint OIDC

```
Issuer:             https://keycloak.lab.local/realms/pbirs-realm
Auth:               https://keycloak.lab.local/realms/pbirs-realm/protocol/openid-connect/auth
Token:              https://keycloak.lab.local/realms/pbirs-realm/protocol/openid-connect/token
JWKS:               https://keycloak.lab.local/realms/pbirs-realm/protocol/openid-connect/certs
Userinfo:           https://keycloak.lab.local/realms/pbirs-realm/protocol/openid-connect/userinfo
Logout:             https://keycloak.lab.local/realms/pbirs-realm/protocol/openid-connect/logout
```

---

## 8. Xây dựng Custom Security Extension cho PBIRS

Custom Security Extension là một .NET assembly (`keycloak-auth.dll`) cài vào PBIRS để thay thế form login mặc định.

### 8.1. Cấu trúc Solution

```
KeycloakPbiRSAuth/
├── KeycloakPbiRSAuth.sln
├── KeycloakPbiRSAuth/
│   ├── KeycloakPbiRSAuth.csproj
│   ├── CustomSecurity.cs          # IAuthenticationExtension
│   ├── LogonForm.cs               # Xử lý logon page
│   ├── KeycloakOidcClient.cs      # OIDC client (token exchange)
│   ├── TokenValidator.cs          # Validate JWT token
│   ├── Configuration.cs           # Đọc config từ web.config
│   └── Web/
│       ├── Logon.aspx             # Login page (redirect to Keycloak)
│       └── KeycloakCallback.aspx  # OIDC callback
├── Install/
│   └── keycloak_pbirs_install.ps1
└── README.md
```

### 8.2. CustomSecurity.cs

```csharp
using System;
using System.Web;
using System.Web.Security;
using Microsoft.ReportingServices.Interfaces;

namespace KeycloakPbiRSAuth
{
    public class CustomSecurity : IAuthenticationExtension2
    {
        public bool IsFormsAuthentication => true;
        public string LocalizedName => "Keycloak PBIRS Authentication";

        public void GetUserInfo(out IUserIdentity userIdentity, out IntPtr userId)
        {
            if (HttpContext.Current?.User?.Identity?.IsAuthenticated == true)
            {
                var username = HttpContext.Current.User.Identity.Name;
                userIdentity = new UserIdentity(username);
                userId = IntPtr.Zero;
                return;
            }
            userIdentity = null;
            userId = IntPtr.Zero;
        }

        public bool AuthenticateUser(string userName, string password, out IUserIdentity userIdentity)
        {
            userIdentity = null;
            // Không dùng password-based auth từ form;
            // OIDC flow xử lý authentication riêng qua callback.
            if (HttpContext.Current?.User?.Identity?.IsAuthenticated == true)
            {
                userIdentity = new UserIdentity(HttpContext.Current.User.Identity.Name);
                return true;
            }
            return false;
        }

        public string AuthenticationType => "KeycloakOIDC";

        public void SetConfiguration(string configuration) { }
        public bool LogonUser(IPrincipal principal) => true;
    }

    public class UserIdentity : IUserIdentity
    {
        public string Name { get; }
        public UserIdentity(string name) => Name = name;
        public byte[] UserToken => null;
    }
}
```

### 8.3. KeycloakOidcClient.cs

```csharp
using System;
using System.Collections.Generic;
using System.Net.Http;
using System.Text.Json;
using System.Threading.Tasks;

namespace KeycloakPbiRSAuth
{
    public class KeycloakOidcClient
    {
        private readonly HttpClient _client = new HttpClient();
        private readonly Configuration _config = Configuration.Instance;

        public async Task<TokenResponse> ExchangeCodeForTokenAsync(string code, string redirectUri)
        {
            var content = new FormUrlEncodedContent(new[]
            {
                new KeyValuePair<string, string>("grant_type", "authorization_code"),
                new KeyValuePair<string, string>("code", code),
                new KeyValuePair<string, string>("redirect_uri", redirectUri),
                new KeyValuePair<string, string>("client_id", _config.ClientId),
                new KeyValuePair<string, string>("client_secret", _config.ClientSecret)
            });

            var response = await _client.PostAsync(_config.TokenEndpoint, content);
            response.EnsureSuccessStatusCode();

            var json = await response.Content.ReadAsStringAsync();
            return JsonSerializer.Deserialize<TokenResponse>(json);
        }

        public async Task<JsonDocument> GetUserInfoAsync(string accessToken)
        {
            var request = new HttpRequestMessage(HttpMethod.Get, _config.UserInfoEndpoint);
            request.Headers.Authorization =
                new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", accessToken);

            var response = await _client.SendAsync(request);
            response.EnsureSuccessStatusCode();
            var json = await response.Content.ReadAsStringAsync();
            return JsonDocument.Parse(json);
        }
    }

    public class TokenResponse
    {
        public string access_token { get; set; }
        public string id_token { get; set; }
        public string refresh_token { get; set; }
        public int expires_in { get; set; }
        public string token_type { get; set; }
        public string session_state { get; set; }
        public string scope { get; set; }
    }
}
```

### 8.4. TokenValidator.cs

```csharp
using System;
using System.Collections.Generic;
using System.IdentityModel.Tokens.Jwt;
using System.Linq;
using System.Net.Http;
using System.Security.Claims;
using System.Text.Json;
using Microsoft.IdentityModel.Tokens;
using Microsoft.IdentityModel.Protocols;
using Microsoft.IdentityModel.Protocols.OpenIdConnect;

namespace KeycloakPbiRSAuth
{
    public class TokenValidator
    {
        private readonly Configuration _config = Configuration.Instance;
        private readonly HttpClient _httpClient = new HttpClient();

        public ClaimsPrincipal ValidateToken(string accessToken)
        {
            try
            {
                var handler = new JwtSecurityTokenHandler();

                var validationParameters = new TokenValidationParameters
                {
                    ValidateIssuer = true,
                    ValidIssuer = _config.Issuer,
                    ValidateAudience = true,
                    ValidAudience = _config.ClientId,
                    ValidateLifetime = true,
                    ClockSkew = TimeSpan.FromMinutes(1),
                    IssuerSigningKeyResolver = (token, securityToken, kid, parameters) =>
                    {
                        var keys = FetchSigningKeysAsync().GetAwaiter().GetResult();
                        return keys.Where(k => k.Kid == kid);
                    }
                };

                return handler.ValidateToken(accessToken, validationParameters, out _);
            }
            catch (Exception ex)
            {
                System.Diagnostics.Trace.WriteLine($"Token validation failed: {ex.Message}");
                return null;
            }
        }

        private async Task<IEnumerable<SecurityKey>> FetchSigningKeysAsync()
        {
            var configManager = new ConfigurationManager<OpenIdConnectConfiguration>(
                _config.MetadataEndpoint, new OpenIdConnectConfigurationRetriever(),
                new HttpDocumentRetriever(_httpClient));

            var config = await configManager.GetConfigurationAsync();
            return config.SigningKeys;
        }

        public string ExtractUsername(ClaimsPrincipal principal)
        {
            return principal?.FindFirst("preferred_username")?.Value
                ?? principal?.FindFirst(ClaimTypes.Name)?.Value
                ?? principal?.FindFirst("sub")?.Value;
        }
    }
}
```

### 8.5. Configuration.cs

```csharp
using System.Configuration;

namespace KeycloakPbiRSAuth
{
    public class Configuration
    {
        public static Configuration Instance { get; } = new Configuration();

        // Keycloak endpoints
        public string Issuer => GetConfig("keycloak:Issuer",
            "https://keycloak.lab.local/realms/pbirs-realm");
        public string AuthorizationEndpoint => GetConfig("keycloak:AuthorizationEndpoint",
            $"{Issuer}/protocol/openid-connect/auth");
        public string TokenEndpoint => GetConfig("keycloak:TokenEndpoint",
            $"{Issuer}/protocol/openid-connect/token");
        public string UserInfoEndpoint => GetConfig("keycloak:UserInfoEndpoint",
            $"{Issuer}/protocol/openid-connect/userinfo");
        public string MetadataEndpoint => GetConfig("keycloak:MetadataEndpoint",
            $"{Issuer}/.well-known/openid-configuration");

        // Client
        public string ClientId => GetConfig("keycloak:ClientId", "pbirs-client");
        public string ClientSecret => GetConfig("keycloak:ClientSecret", "pbirs_secret_2026!");
        public string CallbackPath => GetConfig("keycloak:CallbackPath", "/KeycloakCallback");
        public string LogoutPath => GetConfig("keycloak:LogoutPath", "/KeycloakLogout");

        // Power BI RS
        public string ReportServerUrl => GetConfig("keycloak:ReportServerUrl",
            "https://pbirs.qnet.edu.vn");
        public string Scopes => GetConfig("keycloak:Scopes", "openid profile email");

        private string GetConfig(string key, string defaultValue)
        {
            return ConfigurationManager.AppSettings[key] ?? defaultValue;
        }
    }
}
```

### 8.6. Logon.aspx (Login page - redirect to Keycloak)

```aspx
<%@ Page Language="C#" AutoEventWireup="true" CodeBehind="Logon.aspx.cs" Inherits="KeycloakPbiRSAuth.Web.Logon" %>
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8" />
    <meta http-equiv="refresh" content="0;url=<%= RedirectUrl %>" />
    <title>Đang chuyển hướng đến Keycloak...</title>
</head>
<body>
    <div style="text-align:center; margin-top:100px; font-family:Arial;">
        <h2>Đang chuyển hướng đến trang đăng nhập...</h2>
        <p>Nếu không tự động chuyển tiếp,
           <a href="<%= RedirectUrl %>">bấm vào đây</a>.</p>
    </div>
</body>
</html>
```

**Logon.aspx.cs:**

```csharp
using System;
using System.Web;
using Microsoft.IdentityModel.Protocols.OpenIdConnect;

namespace KeycloakPbiRSAuth.Web
{
    public partial class Logon : System.Web.UI.Page
    {
        public string RedirectUrl { get; private set; }

        protected void Page_Load(object sender, EventArgs e)
        {
            var cfg = Configuration.Instance;
            var returnUrl = HttpUtility.UrlEncode(Request.QueryString["ReturnUrl"] ?? "/reports");

            // State để chống CSRF + lưu ReturnUrl
            var state = $"{Guid.NewGuid()}|{returnUrl}";
            Session["oidc_state"] = state;
            Session["oidc_return_url"] = returnUrl;

            var authParams = new OpenIdConnectMessage
            {
                IssuerAddress = cfg.AuthorizationEndpoint,
                ClientId = cfg.ClientId,
                RedirectUri = cfg.ReportServerUrl + cfg.CallbackPath,
                ResponseType = OpenIdConnectResponseType.Code,
                Scope = cfg.Scopes,
                State = state,
                Nonce = Guid.NewGuid().ToString()
            };

            RedirectUrl = authParams.CreateAuthenticationRequestUrl();
        }
    }
}
```

### 8.7. KeycloakCallback.aspx (OIDC callback handler)

**KeycloakCallback.aspx.cs:**

```csharp
using System;
using System.Web;
using System.Web.Security;
using System.Linq;

namespace KeycloakPbiRSAuth.Web
{
    public partial class KeycloakCallback : System.Web.UI.Page
    {
        protected void Page_Load(object sender, EventArgs e)
        {
            try
            {
                var code = Request.QueryString["code"];
                var state = Request.QueryString["state"];
                var error = Request.QueryString["error"];

                // Lỗi từ Keycloak
                if (!string.IsNullOrEmpty(error))
                {
                    ShowError($"Keycloak error: {error}. {Request.QueryString["error_description"]}");
                    return;
                }

                // Validate state (chống CSRF)
                var savedState = Session["oidc_state"]?.ToString();
                var returnUrl = Session["oidc_return_url"]?.ToString() ?? "/reports";

                if (string.IsNullOrEmpty(code) || state != savedState)
                {
                    ShowError("Invalid request: state mismatch or missing code.");
                    return;
                }

                // Exchange code → token
                var client = new KeycloakOidcClient();
                var tokenResponse = client.ExchangeCodeForTokenAsync(code,
                    Configuration.Instance.ReportServerUrl + Configuration.Instance.CallbackPath)
                    .GetAwaiter().GetResult();

                // Validate token
                var validator = new TokenValidator();
                var principal = validator.ValidateToken(tokenResponse.access_token);

                if (principal == null || !principal.Identity.IsAuthenticated)
                {
                    ShowError("Token validation failed.");
                    return;
                }

                // Lấy username
                var username = validator.ExtractUsername(principal);

                // Tạo session trong PBIRS
                var ticket = new FormsAuthenticationTicket(
                    1, username, DateTime.Now, DateTime.Now.AddHours(8),
                    false, "KeycloakOIDC");

                var cookieValue = FormsAuthentication.Encrypt(ticket);
                Response.Cookies.Add(new HttpCookie(FormsAuthentication.FormsCookieName, cookieValue)
                {
                    HttpOnly = true,
                    Secure = true,
                    Path = "/"
                });

                // Cleanup và redirect
                Session.Remove("oidc_state");
                Session.Remove("oidc_return_url");

                // Log thành công
                System.Diagnostics.Trace.WriteLine(
                    $"PBIRS login success: {username} at {DateTime.Now}");

                Response.Redirect(returnUrl);
            }
            catch (Exception ex)
            {
                System.Diagnostics.Trace.WriteLine($"Callback error: {ex}");
                ShowError($"Internal error: {ex.Message}");
            }
        }

        private void ShowError(string message)
        {
            Response.Clear();
            Response.Write($@"
            <html><body style='font-family:Arial; margin:50px;'>
            <h2>Đăng nhập thất bại</h2>
            <p style='color:red;'>{HttpUtility.HtmlEncode(message)}</p>
            <p><a href='/reports/Logon.aspx'>Thử lại</a></p>
            </body></html>");
            Response.End();
        }
    }
}
```

### 8.8. KeycloakPbiRSAuth.csproj

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net48</TargetFramework>
    <AssemblyName>KeycloakPbiRSAuth</AssemblyName>
    <RootNamespace>KeycloakPbiRSAuth</RootNamespace>
    <SignAssembly>true</SignAssembly>
    <AssemblyOriginatorKeyFile>KeycloakPbiRSAuth.snk</AssemblyOriginatorKeyFile>
  </PropertyGroup>
  <ItemGroup>
    <Reference Include="System" />
    <Reference Include="System.Configuration" />
    <Reference Include="System.Web" />
    <Reference Include="System.Net.Http" />
    <Reference Include="System.IdentityModel" />
    <Reference Include="System.Runtime.Serialization" />
  </ItemGroup>
  <ItemGroup>
    <PackageReference Include="Microsoft.IdentityModel.Protocols.OpenIdConnect" Version="7.*" />
    <PackageReference Include="Microsoft.IdentityModel.Tokens" Version="7.*" />
    <PackageReference Include="System.IdentityModel.Tokens.Jwt" Version="7.*" />
    <PackageReference Include="Microsoft.ReportingServices.Interfaces" Version="1500.*" />
  </ItemGroup>
</Project>
```

> **Tạo strong name key:**
> ```powershell
> & "C:\Program Files\Microsoft SDKs\Windows\v10.0A\bin\NETFX 4.8 Tools\sn.exe" -k KeycloakPbiRSAuth.snk
> ```

---

## 9. Triển khai Custom Extension lên PBIRS

### 9.1. Build Project

```powershell
# Build bằng MSBuild
& "C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe" `
  KeycloakPbiRSAuth.sln /p:Configuration=Release

# Hoặc dotnet build
dotnet build -c Release
```

### 9.2. Copy assembly vào PBIRS

```powershell
# Đường dẫn PBIRS (thay đổi nếu cần)
$RSInstallDir = "C:\Program Files\Microsoft Power BI Report Server\Shared Services\SSRS"
$RSPortalDir  = "C:\Program Files\Microsoft Power BI Report Server\Shared Services\Portal"

# Copy assembly
Copy-Item ".\bin\Release\net48\KeycloakPbiRSAuth.dll" `
  -Destination "$RSInstallDir\SSRS\bin\KeycloakPbiRSAuth.dll" -Force
Copy-Item ".\bin\Release\net48\KeycloakPbiRSAuth.dll" `
  -Destination "$RSPortalDir\bin\KeycloakPbiRSAuth.dll" -Force

# Copy dependencies (Newtonsoft.Json, Microsoft.IdentityModel.*, etc.)
Copy-Item ".\bin\Release\net48\*.dll" `
  -Destination "$RSInstallDir\SSRS\bin\" -Force -Exclude "KeycloakPbiRSAuth.dll"
Copy-Item ".\bin\Release\net48\*.dll" `
  -Destination "$RSPortalDir\bin\" -Force -Exclude "KeycloakPbiRSAuth.dll"
```

### 9.3. Grant Permission cho Assembly

```powershell
# Chạy Caspol để cấp FullTrust cho assembly
$Caspol = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\caspol.exe"

& $Caspol -machine -addgroup All_Code `
  -url "$RSInstallDir\SSRS\bin\KeycloakPbiRSAuth.dll" FullTrust -name "KeycloakPbiRSAuth"

& $Caspol -machine -addgroup All_Code `
  -url "$RSPortalDir\bin\KeycloakPbiRSAuth.dll" FullTrust -name "KeycloakPbiRSAuth.Portal"
```

### 9.4. Add assembly vào GAC (tùy chọn)

```powershell
& "C:\Program Files\Microsoft SDKs\Windows\v10.0A\bin\NETFX 4.8 Tools\gacutil.exe" `
  -if ".\bin\Release\net48\KeycloakPbiRSAuth.dll"
```

---

## 10. Cấu hình Power BI Report Server

### 10.1. Backup cấu hình gốc

```powershell
Copy-Item "$env:RS_RSInstallDir\SSRS\SSRS\rsreportserver.config" `
  "$env:RS_RSInstallDir\SSRS\SSRS\rsreportserver.config.backup"
```

### 10.2. Sửa rsreportserver.config

```xml
<!-- File: C:\Program Files\Microsoft Power BI Report Server\SSRS\SSRS\rsreportserver.config -->
<Configuration>
  <!-- ... -->
  <Authentication>
    <AuthenticationTypes>
      <AuthenticationType>Custom</AuthenticationType>
      <!-- Tắt hết các auth type khác -->
      <!-- <AuthenticationType>RSWindowsNegotiate</AuthenticationType> -->
      <!-- <AuthenticationType>RSWindowsNTLM</AuthenticationType> -->
      <!-- <AuthenticationType>RSWindowsBasic</AuthenticationType> -->
    </AuthenticationTypes>
    <EnableAuthPersistence>true</EnableAuthPersistence>
    <RSWindowsExtendedProtectionLevel>Off</RSWindowsExtendedProtectionLevel>
    <RSWindowsExtendedProtectionScenario>Proxy</RSWindowsExtendedProtectionScenario>
  </Authentication>

  <UI>
    <LogonPagePath>/KeycloakPbiRSAuth/Logon.aspx</LogonPagePath>
  </UI>

  <Security>
    <Extension Name="KeycloakPbiRSAuth" Type="KeycloakPbiRSAuth.CustomSecurity,KeycloakPbiRSAuth">
      <Configuration></Configuration>
    </Extension>
  </Security>

  <AuthenticationTypes>
    <AuthenticationType>KeycloakPbiRSAuth</AuthenticationType>
  </AuthenticationTypes>
  <!-- ... -->
</Configuration>
```

### 10.3. Sửa web.config cho Portal

```xml
<!-- File: C:\Program Files\Microsoft Power BI Report Server\Shared Services\Portal\web.config -->
<configuration>
  <appSettings>
    <!-- Keycloak endpoints -->
    <add key="keycloak:Issuer" value="https://keycloak.lab.local/realms/pbirs-realm" />
    <add key="keycloak:AuthorizationEndpoint" value="https://keycloak.lab.local/realms/pbirs-realm/protocol/openid-connect/auth" />
    <add key="keycloak:TokenEndpoint" value="https://keycloak.lab.local/realms/pbirs-realm/protocol/openid-connect/token" />
    <add key="keycloak:UserInfoEndpoint" value="https://keycloak.lab.local/realms/pbirs-realm/protocol/openid-connect/userinfo" />
    <add key="keycloak:MetadataEndpoint" value="https://keycloak.lab.local/realms/pbirs-realm/.well-known/openid-configuration" />
    <add key="keycloak:ClientId" value="pbirs-client" />
    <add key="keycloak:ClientSecret" value="pbirs_secret_2026!" />
    <add key="keycloak:CallbackPath" value="/KeycloakCallback" />
    <add key="keycloak:ReportServerUrl" value="https://pbirs.qnet.edu.vn" />
    <add key="keycloak:Scopes" value="openid profile email" />
  </appSettings>

  <system.web>
    <authentication mode="Forms">
      <forms name="KeycloakAuth" loginUrl="/KeycloakPbiRSAuth/Logon.aspx"
             timeout="480" slidingExpiration="true" protection="All" />
    </authentication>
    <authorization>
      <deny users="?" />
    </authorization>
    <machineKey validationKey="AutoGenerate,IsolateApps"
                decryptionKey="AutoGenerate,IsolateApps"
                validation="SHA1" decryption="Auto" />
  </system.web>

  <system.webServer>
    <modules>
      <add name="FormsAuthentication" type="System.Web.Security.FormsAuthenticationModule" />
    </modules>
  </system.webServer>
</configuration>
```

### 10.4. Sửa web.config cho Report Server

```xml
<!-- File: C:\Program Files\Microsoft Power BI Report Server\SSRS\SSRS\web.config -->
<configuration>
  <appSettings>
    <!-- Giống portal config ở trên, copy lại -->
    <add key="keycloak:Issuer" value="https://keycloak.lab.local/realms/pbirs-realm" />
    <!-- ... các key khác ... -->
  </appSettings>

  <system.web>
    <authentication mode="Forms">
      <forms name="KeycloakAuth" loginUrl="/KeycloakPbiRSAuth/Logon.aspx"
             timeout="480" slidingExpiration="true" protection="All" />
    </authentication>
    <authorization>
      <deny users="?" />
    </authorization>
  </system.web>
</configuration>
```

### 10.5. Copy các file Web vào thư mục PBIRS

```powershell
# Tạo thư mục
New-Item -ItemType Directory -Path "$RSPortalDir\KeycloakPbiRSAuth" -Force

# Copy Web files từ project
Copy-Item ".\Web\Logon.aspx" "$RSPortalDir\KeycloakPbiRSAuth\" -Force
Copy-Item ".\Web\Logon.aspx.cs" "$RSPortalDir\KeycloakPbiRSAuth\" -Force
Copy-Item ".\Web\KeycloakCallback.aspx" "$RSPortalDir\KeycloakPbiRSAuth\" -Force
Copy-Item ".\Web\KeycloakCallback.aspx.cs" "$RSPortalDir\KeycloakPbiRSAuth\" -Force

# Tương tự cho Report Server
New-Item -ItemType Directory -Path "$RSInstallDir\SSRS\SSRS\KeycloakPbiRSAuth" -Force
Copy-Item ".\Web\Logon.aspx" "$RSInstallDir\SSRS\SSRS\KeycloakPbiRSAuth\" -Force
Copy-Item ".\Web\Logon.aspx.cs" "$RSInstallDir\SSRS\SSRS\KeycloakPbiRSAuth\" -Force
Copy-Item ".\Web\KeycloakCallback.aspx" "$RSInstallDir\SSRS\SSRS\KeycloakPbiRSAuth\" -Force
Copy-Item ".\Web\KeycloakCallback.aspx.cs" "$RSInstallDir\SSRS\SSRS\KeycloakPbiRSAuth\" -Force
```

### 10.6. Import SSL Certificate cho PBIRS

Nếu Keycloak dùng self-signed cert, PBIRS cần trust nó:

```powershell
# Trên PBIRS, import Keycloak cert vào Windows Trust Store
$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
$cert.Import("C:\tmp\keycloak-selfsigned.crt")
$store = New-Object System.Security.Cryptography.X509Certificates.X509Store(
    "Root", "LocalMachine")
$store.Open("ReadWrite")
$store.Add($cert)
$store.Close()
```

Lấy cert từ Keycloak:
```bash
openssl s_client -connect 127.0.0.1:443 -showcerts </dev/null 2>/dev/null | \
  sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' | \
  head -30 > /tmp/keycloak-selfsigned.crt
```

### 10.7. Restart PBIRS

```powershell
Restart-Service "PowerBIReportServer"
Restart-Service "PowerBIReportServerWebService"
Restart-Service "PowerBIReportServerWebAppPool"
```

Kiểm tra log lỗi:
```powershell
Get-EventLog -LogName Application -Source "Power BI Report Server" -Newest 20 | Format-Table
Get-Content "C:\Program Files\Microsoft Power BI Report Server\SSRS\SSRS\LogFiles\*.log" -Tail 50
```

---

## 11. Kiểm tra toàn bộ luồng

### 11.1. Kiểm tra LDAPs sync từ AD qnet.edu.vn

```bash
# Trên Keycloak - đếm users đã sync
curl -s -X GET "https://keycloak.lab.local/admin/realms/pbirs-realm/users/count" \
  -H "Authorization: Bearer <admin-token>" \
  -k
```

### 11.2. Kiểm tra OTP (qua REST)

```bash
# Lấy token với OTP
curl -s -X POST "https://keycloak.lab.local/realms/pbirs-realm/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=pbirs-client" \
  -d "client_secret=pbirs_secret_2026!" \
  -d "username=user1@qnet.edu.vn" \
  -d "password=<AD_PASSWORD>" \
  -d "totp=<OTP_CODE>" \
  -d "grant_type=password" \
  -k | jq .
```

### 11.3. Kiểm tra Power BI RS Login

1. Mở trình duyệt ẩn danh → `https://pbirs.qnet.edu.vn/reports`
2. Trình duyệt sẽ redirect đến Keycloak login
3. Kiểm tra URL redirect:
   ```
   https://keycloak.lab.local/realms/pbirs-realm/protocol/openid-connect/auth?
     client_id=pbirs-client&redirect_uri=https://pbirs.qnet.edu.vn/KeycloakCallback
     &response_type=code&scope=openid+profile+email&state=...
   ```
4. Nhập **username** (`user1`) và **password** (AD password từ qnet.edu.vn)
5. Nếu lần đầu → scan QR OTP (Google Authenticator / Authy) → nhập mã
6. Redirect về PBIRS → thành công
7. Kiểm tra quyền: thử xem report, upload report...

### 11.4. Kiểm tra Token Claims

```bash
# Decode token để kiểm tra preferred_username
ACCESS_TOKEN=$(curl -s -X POST "https://keycloak.lab.local/realms/pbirs-realm/protocol/openid-connect/token" \
  -d "client_id=pbirs-client" \
  -d "client_secret=pbirs_secret_2026!" \
  -d "username=user1@qnet.edu.vn" \
  -d "password=<pass>" \
  -d "totp=<otp>" \
  -d "grant_type=password" -k | jq -r '.access_token')

echo $ACCESS_TOKEN | cut -d '.' -f2 | base64 -d 2>/dev/null | jq .
```

Kiểm tra claim `preferred_username` có giá trị đúng (VD: `user1`).

---

## 12. Khắc phục sự cố

### 12.1. LDAPs connection error

```
javax.net.ssl.SSLHandshakeException: sun.security.validator.ValidatorException:
  PKIX path building failed
```

**Fix:** Import AD CA cert vào Java truststore (xem bước 4.5).

```bash
# Debug SSL handshake
openssl s_client -connect 192.168.100.27:636 -showcerts
```

### 12.2. OIDC redirect loop

**Kiểm tra:**
- `Valid Redirect URIs` trong Keycloak Client: `https://pbirs.qnet.edu.vn/KeycloakCallback`
- Certificate: PBIRS có trust Keycloak cert chưa? (bước 10.6)
- Log Keycloak: `journalctl -u keycloak -f`

### 12.3. Token validation fails

```
IDX10503: Signature validation failed. Unable to match key.
```

**Fix:** Kiểm tra `IssuerSigningKeyResolver` trong `TokenValidator.cs` — cần fetch JWKS đúng URL.

```bash
curl -s "https://keycloak.lab.local/realms/pbirs-realm/protocol/openid-connect/certs" -k | jq .
```

### 12.4. Assembly không load được

```
Could not load file or assembly 'KeycloakPbiRSAuth' or one of its dependencies.
```

**Fix:**
- Assembly có strong-name không? (cần `sn -k KeycloakPbiRSAuth.snk`)
- Assembly có được copy vào cả 2 thư mục SSRS và Portal?
- Code access security đã cấp FullTrust? (bước 9.3)

### 12.5. OTP form không hiển thị

| Check | Action |
|---|---|
| Required Action Configure OTP đã enabled? | Authentication → Required Actions |
| User đã được gán Required Action? | Users → user → Required User Actions |
| Realm Require OTP đã bật? | Realm Settings → Login |

### 12.6. User không có quyền trên PBIRS

**Role Assignment trong PBIRS:**
1. PBIRS Web Portal → **Settings** → **Site Settings**
2. **Security** → **Add group or user**
3. Nhập username (VD: `QNET\user1`) → role: **System User** / **System Administrator**
4. Tại thư mục /Reports → **Manage** → **Security** → thêm user/group với quyền **Content Manager** / **Browser**

---

## 13. Phụ lục: Nâng cấp - Tùy biến giao diện login form

### 13.1. Styled Login Page

```aspx
<!-- Logon.aspx - phiên bản có giao diện Keycloak theme -->
<%@ Page Language="C#" AutoEventWireup="true" CodeBehind="Logon.aspx.cs" Inherits="KeycloakPbiRSAuth.Web.Logon" %>
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>Đăng nhập - Power BI Report Server</title>
    <style>
        * { margin:0; padding:0; box-sizing:border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #1a1a2e 0%, #16213e 50%, #0f3460 100%);
            min-height: 100vh; display: flex; align-items: center; justify-content: center;
        }
        .login-card {
            background: #fff; border-radius: 12px; padding: 40px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3); width: 420px; max-width: 90vw;
        }
        .login-card h1 {
            color: #1a1a2e; font-size: 24px; margin-bottom: 8px;
        }
        .login-card p {
            color: #666; font-size: 14px; margin-bottom: 24px;
        }
        .login-btn {
            display: block; width: 100%; padding: 14px;
            background: #0f3460; color: #fff; border: none; border-radius: 6px;
            font-size: 16px; cursor: pointer; transition: background 0.3s;
            text-decoration: none; text-align: center;
        }
        .login-btn:hover { background: #1a5276; }
        .spinner { display:none; margin: 20px auto; border: 3px solid #f3f3f3;
            border-top: 3px solid #0f3460; border-radius: 50%;
            width: 40px; height: 40px; animation: spin 1s linear infinite; }
        @keyframes spin { 0% { transform: rotate(0deg); } 100% { transform: rotate(360deg); } }
        .footer { margin-top: 20px; text-align: center; font-size: 12px; color: #999; }
    </style>
</head>
<body>
    <div class="login-card">
        <h1>Power BI Report Server</h1>
        <p>Đăng nhập bằng tài khoản doanh nghiệp (qnet.edu.vn)</p>
        <a href="<%= RedirectUrl %>" class="login-btn" onclick="showSpinner()">
            Đăng nhập với Keycloak
        </a>
        <div class="spinner" id="spinner"></div>
        <div class="footer">Bảo mật bởi Keycloak SSO + OTP</div>
    </div>
    <script>
        function showSpinner() {
            document.querySelector('.login-btn').style.display = 'none';
            document.getElementById('spinner').style.display = 'block';
        }
    </script>
</body>
</html>
```

### 13.2. Xử lý Logout

Thêm endpoint logout để xóa session cả PBIRS và Keycloak:

```csharp
// KeycloakLogout.aspx.cs
using System;
using System.Web;
using System.Web.Security;

namespace KeycloakPbiRSAuth.Web
{
    public partial class KeycloakLogout : System.Web.UI.Page
    {
        protected void Page_Load(object sender, EventArgs e)
        {
            // Clear PBIRS auth cookie
            FormsAuthentication.SignOut();

            // Clear session
            Session.Clear();
            Session.Abandon();

            // Expire all cookies
            foreach (string cookie in Request.Cookies)
            {
                var c = new HttpCookie(cookie) { Expires = DateTime.Now.AddDays(-1) };
                Response.Cookies.Add(c);
            }

            // Redirect to Keycloak logout
            var cfg = Configuration.Instance;
            var logoutUrl =
                $"{cfg.Issuer}/protocol/openid-connect/logout?" +
                $"post_logout_redirect_uri={HttpUtility.UrlEncode(cfg.ReportServerUrl)}" +
                $"&id_token_hint={Request.QueryString["id_token_hint"]}";

            Response.Redirect(logoutUrl);
        }
    }
}
```

Thêm vào web.config:
```xml
<add key="keycloak:LogoutPath" value="/KeycloakLogout" />
```

### 13.3. Cấu hình Security Group PBIRS trong AD

```powershell
# Tạo groups PBIRS trong AD qnet.edu.vn
$groups = @(
    @{Name="PBIRS-Admins"; Description="PBIRS System Administrators"},
    @{Name="PBIRS-ContentManagers"; Description="PBIRS Content Managers"},
    @{Name="PBIRS-Viewers"; Description="PBIRS Report Viewers"},
    @{Name="PBIRS-Publishers"; Description="PBIRS Report Publishers"}
)

foreach ($g in $groups) {
    New-ADGroup -Name $g.Name -GroupScope Global `
      -Description $g.Description `
      -Path "CN=Users,DC=qnet,DC=edu,DC=vn"
}

# Add users
Add-ADGroupMember -Identity "PBIRS-Admins" -Members "admin1"
Add-ADGroupMember -Identity "PBIRS-Viewers" -Members "user1", "user2"
```

### 13.4. Role Assignment Script cho PBIRS

```powershell
# PowerShell Module cho PBIRS REST API
# Cài đặt: Install-Module -Name ReportingServicesTools

Import-Module ReportingServicesTools

$rsUri = "https://pbirs.qnet.edu.vn/reports"

# System Role Assignment
New-RsSystemRoleAssignment -ReportServerUri $rsUri `
  -UserName "QNET\admin1" -Roles "System Administrator"

New-RsSystemRoleAssignment -ReportServerUri $rsUri `
  -UserName "QNET\user1" -Roles "System User"

# Folder Role Assignment
New-RsFolderRoleAssignment -ReportServerUri $rsUri `
  -CatalogPath "/" -UserName "QNET\admin1" -Roles "Content Manager"

New-RsFolderRoleAssignment -ReportServerUri $rsUri `
  -CatalogPath "/" -UserName "QNET\user1" -Roles "Browser"
```

---

## Tài liệu tham khảo

- Keycloak LDAP: https://www.keycloak.org/docs/latest/server_admin/#_ldap
- Keycloak OTP: https://www.keycloak.org/docs/latest/server_admin/#_otp-policy
- Power BI RS Custom Security: https://learn.microsoft.com/en-us/power-bi/report-server/extensions/secure-development/custom-security
- Reporting Services Security: https://learn.microsoft.com/en-us/sql/reporting-services/security/reporting-services-security
- Power BI RS REST API: https://learn.microsoft.com/en-us/power-bi/report-server/rest-api
- Keycloak OIDC: https://www.keycloak.org/docs/latest/securing_apps/#_oidc
