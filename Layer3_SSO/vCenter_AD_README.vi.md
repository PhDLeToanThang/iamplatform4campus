# Phần 1. Tham khảo các công nghệ iAM Security Platform:

>> Tôi đang có:
- 01 vCenter Appliance v8.0u3 VM chạy ở dải ipv4 thuộc Management Layer network (ipv4 192.168.100.98), 
- 01 AD Primary Domain v2016 (ipv4 192.168.100.20) domain: cloud.local và chạy delegated với 
- 01 AD Backup domain v2019 (ipv4 192.168.100.25) domain: cloud.local. 
- 01 AD Primary Domain v2019 (ipv4 192.168.100.50) domain: company.local
 Có thể hướng dẫn chi tiết từng bước việc lựa chọn các phương án hợp lý, phù hợp cho tích hợp SSO, phân quyền bằng Group name của AD user, groups, gpo và Username sẽ theo email duy nhất để tránh cách dùng UPN khi có nhiều Multi-Domain AD Local? 
 - Về các tiêu chí để chọn phương án hợp lý cần đáp ứng kỹ thuật mô hình kết nối LDAPs tạo iDP trên vCenter support qua LDAP/s và cấu hình SAML2 hoặc OpenID connect để cấu hình.

---

Cảm ơn bạn đã cung cấp thông tin rất chi tiết. Với mô hình bạn đang triển khai, mục tiêu là tích hợp **vCenter 8.0u3** với **Active Directory (AD)** để sử dụng **SSO**, phân quyền theo **Group AD**, và đảm bảo **định danh người dùng duy nhất bằng email** (thay vì UPN) trong môi trường có khả năng mở rộng sang **multi-domain**.

Dưới đây là hướng dẫn chi tiết từng bước, kèm theo phân tích các phương án phù hợp với tiêu chí kỹ thuật bạn đưa ra:

---

## 🎯 **Mục tiêu**
1. Tích hợp vCenter với AD qua LDAPs (bảo mật).
2. Sử dụng Group AD để phân quyền.
3. Định danh người dùng bằng email (mail attribute) thay vì UPN.
4. Hỗ trợ mở rộng cho multi-domain AD.
5. Hỗ trợ iDP qua LDAPs và SAML2/OpenID Connect.

---

## 🧩 **Phân tích các phương án tích hợp**

### **1. Phương án tích hợp AD vào vCenter**
| Phương án | Ưu điểm | Nhược điểm |
|----------|---------|------------|
| **Join vCenter vào AD domain** | Dễ cấu hình, hỗ trợ Kerberos, dùng UPN | Không linh hoạt với multi-domain, không dùng email làm định danh |
| **Sử dụng LDAPs (LDAPS) để tích hợp AD** ✅ | Bảo mật, linh hoạt, dùng được nhiều domain, có thể dùng `mail` làm định danh | Cần cấu hình chi tiết, cần chứng chỉ |
| **SAML2 hoặc OpenID Connect với iDP trung gian (Azure AD, Keycloak, ADFS)** | Hỗ trợ xác thực hiện đại, dễ mở rộng, dùng email | Cần triển khai thêm iDP trung gian |

✅ **Khuyến nghị**: **LDAPs + SAML2/OpenID Connect** là phương án tối ưu cho mô hình của bạn.

---

## 🛠️ **Chi tiết từng bước cấu hình**

### **Bước 1: Chuẩn bị AD**
- Đảm bảo AD Primary và Backup đều đồng bộ.
- Cấu hình thuộc tính `mail` cho tất cả user.
- Tạo các **Security Group** trong AD để phân quyền (VD: `vCenter-Admins`, `vCenter-ReadOnly`).
- Cài đặt chứng chỉ SSL cho dịch vụ LDAPs (TCP 636).

### **Bước 2: Cấu hình LDAPs trên vCenter**
1. Truy cập vCenter → **Administration** → **Single Sign-On** → **Configuration** → **Identity Sources**.
2. Chọn **Add Identity Source** → **Active Directory over LDAP**.
3. Nhập thông tin:
   - **Base DN**: `dc=yourdomain,dc=local`
   - **Domain name**: `yourdomain.local`
   - **Primary server URL**: `ldaps://192.168.100.20:636`
   - **Secondary server URL**: `ldaps://192.168.100.25:636`
   - **Bind DN**: `CN=ldapbind,OU=ServiceAccounts,DC=yourdomain,DC=local`
   - **User Attribute**: `mail` ✅
   - **Group Attribute**: `cn`
4. Import chứng chỉ CA nếu cần.

### **Bước 3: Phân quyền theo Group AD**
1. Truy cập **Global Permissions** trong vCenter.
2. Add Group từ AD (VD: `yourdomain.local\vCenter-Admins`).
3. Gán quyền tương ứng (Administrator, ReadOnly...).

### **Bước 4: Cấu hình iDP (SAML2/OpenID Connect)**
- Nếu bạn có iDP như **Keycloak**, **ADFS**, hoặc **Azure AD**, bạn có thể:
  - Cấu hình vCenter làm **Service Provider (SP)**.
  - Cấu hình iDP để xác thực qua email.
  - Import metadata từ iDP vào vCenter.

---

## 📌 **Tiêu chí lựa chọn phương án phù hợp**
| Tiêu chí | LDAPs | SAML2/OpenID | Join AD |
|---------|-------|--------------|---------|
| Bảo mật | ✅ | ✅ | ❌ (nếu không dùng LDAPS) |
| Dùng email định danh | ✅ | ✅ | ❌ |
| Hỗ trợ multi-domain | ✅ | ✅ | ❌ |
| Dễ cấu hình | Trung bình | Trung bình - Khó | Dễ |
| Phân quyền theo Group | ✅ | ✅ | ✅ |

---

## 📎 Gợi ý thêm
- Nếu bạn muốn triển khai iDP nội bộ, **Keycloak** là lựa chọn mã nguồn mở mạnh mẽ, hỗ trợ cả LDAPs và SAML2/OIDC.
- Đảm bảo đồng bộ thời gian giữa vCenter và AD để tránh lỗi xác thực.
- Kiểm tra firewall mở cổng TCP 636 (LDAPs), 443 (HTTPS), 389 (nếu dùng LDAP thường).

---

>> Hỗ trợ tạo sơ đồ kiến trúc kết nối giữa vCenter 7x/8x, AD và iDP (có thể KEYCLOAK/ADFS) theo mô hình kết nối LDAPs với OpenID connect/SAML2 không vẽ kiểu Drawio (không cần 3D)để rõ nén, chữ viết rõ ràng?

***Sơ đồ kiến trúc kết nối giữa vCenter 7.x/8.x, Active Directory (Primary & Backup), và iDP (Keycloak hoặc ADFS) sử dụng LDAPs và OpenID Connect/SAML2:***

![image](https://github.com/PhDLeToanThang/iamplatform4campus/blob/main/Layer3_SSO/SAML2_vCenter_Keycloak.drawio.svg)

---

## Có thể giải thích thêm về SAML2 và OpenID Connect trong iDP:

Tuyệt vời! Mình sẽ giải thích rõ ràng và dễ hiểu về **SAML2** và **OpenID Connect (OIDC)** trong bối cảnh sử dụng với **Identity Provider (iDP)** như **Keycloak** hoặc **ADFS**, đặc biệt khi tích hợp với **vCenter**.

---

## 🔐 **1. SAML2 (Security Assertion Markup Language 2.0)**

### ✅ **Đặc điểm chính:**
- Dựa trên **XML**.
- Là giao thức **SSO (Single Sign-On)** phổ biến trong môi trường doanh nghiệp.
- vCenter hỗ trợ SAML2 để xác thực người dùng thông qua iDP.

### 🧭 **Luồng hoạt động:**
1. Người dùng truy cập vCenter.
2. vCenter chuyển hướng người dùng đến iDP (Keycloak/ADFS).
3. iDP xác thực người dùng (thường qua AD).
4. iDP trả về **SAML Assertion** (XML chứa thông tin người dùng).
5. vCenter đọc assertion và cấp quyền truy cập.

### 📌 **Ưu điểm:**
- Bảo mật cao.
- Hỗ trợ phân quyền theo Group AD.
- Không cần lưu mật khẩu trên vCenter.

---

## 🔐 **2. OpenID Connect (OIDC)**

### ✅ **Đặc điểm chính:**
- Dựa trên **OAuth 2.0**.
- Dùng **JSON Web Token (JWT)** thay vì XML.
- Hiện đại hơn, dễ tích hợp với ứng dụng web/mobile.

### 🧭 **Luồng hoạt động:**
1. Người dùng truy cập vCenter (nếu hỗ trợ OIDC).
2. vCenter chuyển hướng đến iDP (Keycloak/Azure AD...).
3. iDP xác thực người dùng.
4. iDP trả về **ID Token (JWT)** chứa thông tin người dùng.
5. vCenter xác minh token và cấp quyền.

### 📌 **Ưu điểm:**
- Dễ tích hợp với hệ thống hiện đại.
- Token nhẹ, dễ xử lý.
- Hỗ trợ xác thực đa yếu tố (MFA), PKCE...

---

## 🆚 **So sánh**

| Tiêu chí                  | SAML2                         | OpenID Connect (OIDC)         |
|---------------------------|-------------------------------|-------------------------------|
| Định dạng dữ liệu         | XML                           | JSON (JWT)                    |
| Giao thức nền             | SAML                          | OAuth 2.0                     |
| Dễ tích hợp               | Trung bình                    | Dễ hơn                        |
| Hỗ trợ MFA                | Có                            | Có                            |
| Hỗ trợ phân quyền AD      | Có (qua Group claim)          | Có (qua claim hoặc scope)     |
| Phù hợp với vCenter       | ✅ (vCenter hỗ trợ chính thức) | ❌ (OIDC chưa hỗ trợ trực tiếp trên vCenter 8.0u3) |

> 📌 **Lưu ý**: vCenter hiện tại **chính thức hỗ trợ SAML2**, còn **OIDC chưa được hỗ trợ trực tiếp**. Tuy nhiên, bạn có thể dùng OIDC với các ứng dụng khác hoặc thông qua proxy iDP như Keycloak.

---

>> Làm thế nào để cấu hình Keycloak với vCenter?
_hướng dẫn từng bước để cấu hình Keycloak làm Identity Provider (iDP) sử dụng SAML2 để tích hợp với vCenter 7.x/8.x:_

🧩 Tổng quan kiến trúc:

- vCenter đóng vai trò Service Provider (SP).

- Keycloak đóng vai trò Identity Provider (iDP).

- Giao thức xác thực: SAML2.

- Người dùng đăng nhập vào vCenter → được chuyển hướng đến Keycloak → xác thực → quay lại vCenter với token.

🛠️ Bước 1: Cấu hình Realm và Client trong Keycloak

1.1. Truy cập Keycloak Admin Console

- URL: https://<keycloak-host>:8443/auth

- Đăng nhập bằng tài khoản admin.

1.2. Tạo Realm (nếu cần)

- Vào menu Realm → Add Realm → đặt tên (VD: vcenter-realm).

1.3. Tạo Client cho vCenter

- Vào Clients → Create:
		
		- Client ID: vcenter
		
		- Client Protocol: saml
		
		- Root URL: để trống
		
		- Nhấn Save
		
1.4. Cấu hình Client:

- Valid Redirect URIs: https://<vcenter-fqdn>/ui/*

- Base URL: https://<vcenter-fqdn>/ui

- Master SAML Processing URL: https://<vcenter-fqdn>/ui/sso/saml/acs

- IDP-Initiated SSO URL Name: vcenter

- Force Name ID Format: ON

- Name ID Format: email

- Signature Algorithm: RSA_SHA256

- SAML Signature Key Name: KEY_ID

- Encrypt Assertions: OFF

🔐 Bước 2: Cấu hình xác thực người dùng trong Keycloak:

- Vào Users → tạo user hoặc đồng bộ từ LDAP (nếu đã tích hợp AD).

- Đảm bảo mỗi user có thuộc tính email chính xác.

- Gán user vào các Group nếu bạn muốn phân quyền theo Group trong vCenter.

📄 Bước 3: Export Metadata từ Keycloak:

- Truy cập: https://<keycloak-host>:8443/auth/realms/<realm-name>/protocol/saml/descriptor

- Tải file XML metadata này để import vào vCenter.
  
⚙️ Bước 4: Cấu hình vCenter để sử dụng Keycloak làm iDP:

- Truy cập vCenter → Administration → Single Sign-On → Configuration → Identity Provider.

- Chọn SAML Identity Provider (iDP) → Add.
	
	- Nhập thông tin:
   	
   	- Alias: keycloak
   	  
	- SAML Metadata: import file XML từ Keycloak.

	- Nhấn Save.
   
🧪 Bước 5: Kiểm tra đăng nhập:

- Truy cập vCenter → chọn Use external identity provider.
  
- Chọn Keycloak → đăng nhập bằng user Keycloak.
  
- Nếu thành công, bạn sẽ được chuyển về vCenter với quyền tương ứng.
  
🧠 Gợi ý phân quyền theo Group AD (nếu dùng LDAP trong Keycloak)

- Trong Keycloak, đồng bộ Group từ AD.
  
- Gán Group claim trong SAML assertion.
  
- Trong vCenter, phân quyền theo Group name từ SAML assertion.

---

## phân quyền trong vCenter và trong trường hợp cần thêm phân quyền tự động từ KEYCLOAK thì mô tả cơ chế cụ thể

### 🔐 Phân quyền trong vCenter và cơ chế phân quyền tự động từ Keycloak

---

## 🧩 1. Phân quyền trong vCenter

vCenter sử dụng mô hình phân quyền dựa trên:

- **User hoặc Group** (từ vCenter local, AD, hoặc iDP như SAML2).
- **Role**: Tập hợp các quyền (privileges) như `Read-only`, `Administrator`, `Virtual Machine User`, v.v.
- **Object**: Mức tài nguyên áp dụng quyền (Datacenter, Cluster, VM, Folder...).
- **Permission** = User/Group + Role + Object

### 🔄 Cách phân quyền:
1. Truy cập: `vCenter > Administration > Access Control > Global Permissions`
2. Chọn: `Add Permission`
3. Chọn: `User/Group` từ nguồn xác thực (AD hoặc iDP)
4. Gán: `Role` và chọn `Propagate to children` nếu cần

---

## 🧠 2. Phân quyền tự động từ Keycloak (qua SAML2)

Keycloak có thể gửi thông tin **Group hoặc Role** trong **SAML Assertion**, vCenter có thể sử dụng để phân quyền nếu được ánh xạ đúng.

### ✅ Điều kiện:
- vCenter phải được cấu hình để nhận **SAML Assertion** từ Keycloak.
- Keycloak phải gửi **Group hoặc Role claim** trong assertion.
- Các Group đó phải được ánh xạ đúng trong vCenter.

---

## ⚙️ Cơ chế hoạt động:

### 🔁 Luồng phân quyền tự động:

1. **Người dùng đăng nhập vCenter** → được chuyển hướng đến **Keycloak**.
2. **Keycloak xác thực người dùng** → lấy thông tin Group từ AD hoặc nội bộ.
3. **Keycloak gửi SAML Assertion** chứa:
   - `NameID` (email hoặc username)
   - `Group` hoặc `Role` (qua attribute)
4. **vCenter nhận assertion** → ánh xạ Group vào quyền đã cấu hình sẵn.

---

## 🛠️ Cấu hình Keycloak để gửi Group trong SAML Assertion

1. Vào **Client** cấu hình cho vCenter → tab **Mappers**
2. Thêm mapper:
   - **Name**: `groups`
   - **Mapper Type**: `Group list`
   - **SAML Attribute Name**: `groups`
   - **Friendly Name**: `groups`
   - **SAML Attribute NameFormat**: `Basic`
3. Đảm bảo user có Group trong Keycloak hoặc được đồng bộ từ AD.

---

## 🛠️ Cấu hình vCenter để phân quyền theo Group từ SAML

1. Truy cập: `vCenter > Administration > Single Sign-On > Users and Groups`
2. Chọn: `Add Group` → nhập đúng tên Group từ SAML Assertion
3. Truy cập: `Global Permissions` → Add Group → Gán Role

---

## 📌 Ví dụ thực tế:

- User `alice@example.com` thuộc Group `vcenter-admins` trong Keycloak
- Keycloak gửi SAML Assertion với:
  ```xml
  <saml:Attribute Name="groups">
    <saml:AttributeValue>vcenter-admins</saml:AttributeValue>
  </saml:Attribute>
  ```
- vCenter đã có Group `vcenter-admins` và gán Role `Administrator`
- Khi Alice đăng nhập, vCenter tự động cấp quyền theo Group

---

Bạn có muốn mình tạo thêm:
- ✅ Mẫu file XML metadata cho Keycloak để import vào vCenter?
- ✅ Mẫu SAML Assertion có chứa Group?
- ✅ Sơ đồ minh họa cơ chế phân quyền tự động từ Keycloak?

---

# Phục lục: Để cấu hình LDAPs (LDAPS) trên cổng 636 cho Active Directory Windows Server 2016/2019, bạn cần có chứng chỉ số hợp lệ được gán cho dịch vụ Directory Services (NTDS). Dưới đây là hướng dẫn chi tiết theo hai phương án:

Để cấu hình **LDAPs (LDAPS) trên cổng 636** cho **Active Directory Windows Server 2016/2019**, bạn cần có **chứng chỉ số hợp lệ** được gán cho dịch vụ **Directory Services (NTDS)**. Dưới đây là hướng dẫn chi tiết theo hai phương án:

---

## ✅ **PHƯƠNG ÁN 1: Dùng CA nội bộ (Enterprise CA)**

### 🔧 Bước 1: Cài đặt Enterprise CA trên Windows Server
1. Mở **Server Manager** → **Add Roles and Features**
2. Chọn **Active Directory Certificate Services**
3. Chọn **Certification Authority** → Tiếp tục cài đặt
4. Sau khi cài xong, mở **Certification Authority** để quản lý

### 🔧 Bước 2: Tạo Template chứng chỉ cho LDAPS
1. Mở **Certification Authority** → Chuột phải vào **Certificate Templates** → **Manage**
2. Tìm template **Kerberos Authentication** hoặc **Domain Controller Authentication**
3. Chuột phải → **Duplicate Template**
4. Đặt tên mới (VD: `LDAPs Template`)
5. Trong tab **Subject Name**:
   - Chọn: **Build from this Active Directory information**
   - Subject name format: **Fully Distinguished Name**
6. Trong tab **Extensions**:
   - Đảm bảo có **Server Authentication (1.3.6.1.5.5.7.3.1)**
7. Trong tab **Security**:
   - Thêm nhóm `Domain Controllers` → Cho phép `Enroll` và `Autoenroll`
8. Lưu lại

### 🔧 Bước 3: Publish Template và cấp chứng chỉ
1. Quay lại **Certification Authority**
2. Chuột phải vào **Certificate Templates** → **New → Certificate Template to Issue**
3. Chọn template vừa tạo (`LDAPs Template`)
4. Trên **Domain Controller**, chạy lệnh:
   ```powershell
   gpupdate /force
   certreq -enroll -machine
   ```
5. Kiểm tra chứng chỉ đã được cấp tại:
   `certlm.msc > Personal > Certificates`

### 🔧 Bước 4: Kiểm tra LDAPS hoạt động
- Kiểm tra port 636:
  ```powershell
  Test-NetConnection -ComputerName localhost -Port 636
  ```
- Hoặc dùng công cụ như **Ldp.exe** để kết nối LDAPS

---

## ✅ **PHƯƠNG ÁN 2: Dùng chứng chỉ từ Let's Encrypt**

### ⚠️ Lưu ý:
- Let's Encrypt không cấp chứng chỉ cho **hostname nội bộ** (VD: `dc01.local`).
- Bạn cần có **FQDN hợp lệ** (VD: `dc01.example.com`) và trỏ DNS về IP nội bộ.
- Cần dùng công cụ như **win-acme** để lấy chứng chỉ.

### 🔧 Bước 1: Cài win-acme
1. Tải từ: https://www.win-acme.com/
2. Giải nén và chạy `wacs.exe` với quyền admin

### 🔧 Bước 2: Cấu hình chứng chỉ
1. Chọn: `Create new certificate (full options)`
2. Chọn: `Manual input` → nhập FQDN của DC
3. Chọn: `Single binding or manual`
4. Chọn: `Store certificate in Windows Certificate Store`
5. Sau khi hoàn tất, chứng chỉ sẽ nằm trong `certlm.msc > Personal`

### 🔧 Bước 3: Gán chứng chỉ cho dịch vụ LDAP
1. Mở Registry Editor:
   ```
   HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\NTDS\Parameters
   ```
2. Tạo giá trị `REG_SZ` tên: `LDAPSSL Certificate`
3. Dán **Thumbprint** của chứng chỉ (không có khoảng trắng)
4. Khởi động lại dịch vụ AD hoặc reboot máy chủ

---

## 📌 Kiểm tra LDAPS hoạt động

- Dùng `ldp.exe`:
  - Connect → Server: `dc01.example.com`, Port: `636`, SSL: ✅
- Dùng PowerShell:
  ```powershell
  Test-NetConnection -ComputerName dc01.example.com -Port 636
  ```

---

Bạn có muốn mình tạo **sơ đồ minh họa kiến trúc LDAPS với CA nội bộ hoặc Let's Encrypt**, hoặc **mẫu script tự động hóa cấu hình CA và cấp chứng chỉ** không?

---

# Phụ lục: Nhà cung cấp và Giải pháp IAM/PIM/PAM:

```vendors_list
1. CyberArk:
- CyberArk Identity Security
- CyberArk Privileged Access Security
- CyberArk Alero

2. BeyondTrust:
- BeyondTrust Password Safe
- BeyondTrust Privileged Remote Access
- BeyondTrust Endpoint Privilege Management

3. Centrify:
- Centrify Identity Services
- Centrify Privileged Access Management

4. Thycotic:
- Thycotic Secret Server
- Thycotic Privilege Manager
- Thycotic Privilege Manager for Unix/Linux

5. Broadcom (CA Technologies):
- CA Identity Suite
- CA Privileged Access Management

6. Micro Focus:
- Micro Focus NetIQ Identity Governance
- Micro Focus NetIQ Privileged Account Manager

7. Oracle:
- Oracle Identity Management
- Oracle Privileged Account Manager

8. Hitachi ID:
- Hitachi ID Identity Manager
- Hitachi ID Privileged Access Manager

9. RSA (Dell Technologies):
- RSA Identity Governance and Lifecycle
- RSA SecurID Suite
- RSA SecurID Access

10. Omada:
- Omada Identity Suite
- Omada Identity Governance & Administration

11. Saviynt:
- Saviynt Identity Governance and Administration
- Saviynt Privilege Access Management

12. SecurEnds:
- SecurEnds IAM
- SecurEnds PAM

13. Identity Automation:
- Identity Automation RapidIdentity
- Identity Automation RapidIdentity Privileged Access Management

14. Microsoft:
- Microsoft Azure Active Directory (AAD)
- Microsoft Azure AD Privileged Identity Management

15. SailPoint:
- SailPoint IdentityNow
- SailPoint IdentityIQ

16. Okta:
- Okta Identity Cloud
- Okta Advanced Server Access

17. Ping Identity:
- Ping Identity PingOne
- Ping Identity PingDirectory

18. Google:
- Google Identity Platform
- Google Cloud Identity

19. VMware:
- VMware Workspace ONE
- VMware Identity Manager

20. IBM:
- IBM Security Identity Governance and Intelligence (IGI)
- IBM Security Verify

21. Entrust:
- Entrust IdentityGuard
- Entrust Identity as a Service

22. Akamai:
- Akamai Enterprise Application Access (EAA)
- Akamai Identity Cloud

23. Auth0 (Okta):
- Auth0 Identity Platform
- Auth0 Authorization Extension

24. RSA:
- RSA Identity Governance and Lifecycle
- RSA Archer

25. Quest Software:
- Quest Identity Manager
- Quest Privilege Manager

26. Secret Double Octopus:
- Secret Double Octopus Authentication
- Secret Double Octopus Access Control

27. OpenText:
- OpenText Identity and Access Management
- OpenText Access Rights Management

28. Evidian (Atos):
- Evidian Identity and Access Manager
- Evidian Privileged Access Management

29. ProofID:
- ProofID IAM
- ProofID PAM

30. SecZetta:
- SecZetta Identity Management
- SecZetta Identity Access Management

31. Oracle (acquired by Broadcom):
- Oracle Identity Cloud Service
- Oracle Identity Governance Suite

32. Thales (formerly Gemalto):
- Thales SafeNet Authentication
- Thales SafeNet Trusted Access

33. ForgeRock:
- ForgeRock Identity Platform
- ForgeRock Identity Governance

34. SecureAuth:
- SecureAuth Identity Platform
- SecureAuth Access Management

35. RSA (acquired by Symphony Technology Group):
- RSA Identity Governance and Lifecycle
- RSA NetWitness

36. Idaptive (a subsidiary of CyberArk):
- Idaptive Next-Gen Access
- Idaptive Identity Services Platform

37. HID Global:
- HID Identity Assurance
- HID Identity and Access Management

38. Ping Identity (acquired by Vista Equity Partners):
- Ping Identity PingAccess
- Ping Identity PingFederate

39. Zoho:
- Zoho Identity
- Zoho Vault

40. ManageEngine (a division of Zoho):
- ManageEngine ADManager Plus
- ManageEngine Password Manager Pro

41. LogMeIn:
- LogMeIn LastPass
- LogMeIn Central

42. Netwrix:
- Netwrix Auditor
- Netwrix Identity Management

43. RSA (acquired by STG):
- RSA Identity Governance and Lifecycle
- RSA Archer

44. Avatier:
- Avatier Identity Anywhere
- Avatier Identity Management Suite

45. AlertEnterprise:
- AlertEnterprise Identity Governance and Administration
- AlertEnterprise Access Management

46. SecureLink:
- SecureLink Privileged Access Management
- SecureLink Identity Management

47. Cisco:
- Cisco Identity Services Engine (ISE)
- Cisco Duo Security

48. Keycloak (Red Hat):
- Keycloak Identity and Access Management
- Keycloak Single Sign-On

49. Thales (acquired by Entrust):
- Thales SafeNet Authentication
- Thales SafeNet Trusted Access

50. Foxpass:
- Foxpass Identity and Access Management
- Foxpass Privileged Access Management
```

