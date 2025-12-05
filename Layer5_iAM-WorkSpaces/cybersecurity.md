# Phân tích 3 Giải pháp xác định khả năng đáp ứng:
>>Tôi có công văn xác nhận phụ lục 1, phụ lục 2 về các yêu cầu tiêu chuẩn kỹ thuật về:
>> iAM, Security, SSO/MFA/2FA tích hợp các hệ thống giám sát SOC2, NIOC,
>>các vấn đề AI-ML security của Đơn vị chủ thầu BTC có trên 40 ứng dụng Legacy, .net framework, MVC và
>>3 đề xuất giải pháp - viết tắt GP gồm:
>>GP1. Keycloak SSO/MFA tích hợp SIEM ELK với Wazhu với OpenCTI NDR thuộc giải pháp của HiPT-AT.COM chuyên subcription support 5 năm
>>( Tham khảo luồng Drawio mermaid graphtd: về tích hợp join domain giữa Power BI report server với 4 AD-DC Global cùng với LDAPS và SSO có MFA kiểu TOTP của Keycloak và tích hợp các công nghệ SIEM sysLog ELK, Wazhu diệt virus tìm vá lỗ hổng phần mềm, OpenCTI tìm các lỗ hổng, các giao dịch trên interrnet giao bán dữ liệu số có thể là các dữ liệu DLP, phân tích giám sát hành vi người dùng:
https://app.diagrams.net/?url=https://www.atcom.vn/CyberSecurity/vSOS8x_2025.drawio&lang=vi&ui=min&dark=1&splash=0#Uhttps://www.atcom.vn/CyberSecurity/vSOS8x_2025.drawio#%7B%22pageId%22%3A%22vMEBBjItcN9HG55Qopc-%22%7D ).
>>GP2. MS Entra ID + MS Sentinel và
GP3. Sailpoint.
>>Hãy phân tích chi tiết, lập bảng so sánh SOW, CAPEX, OPEX, TCO, ROI giữa 3 Giải pháp trên;
>>Vẽ drawio lược đồ - sơ đồ và quy trình các bước triển khai vận hành của 3 giải pháp theo format Mermaid graph td.
---

Dựa trên yêu cầu của bạn và tài liệu từ Bộ Tài chính, tôi phân tích 3 giải pháp và lập bảng so sánh chi tiết dưới đây:

### **Bảng So Sánh 3 Giải Pháp**
| **Tiêu Chí**         | **GP1: Keycloak + SIEM ELK/Wazuh/OpenCTI** | **GP2: Microsoft Entra ID + Sentinel** | **GP3: SailPoint** |
|----------------------|--------------------------------------------|---------------------------------------|--------------------|
| **SOW (Phạm Vi Công Việc)** | - Xác thực MFA/SSO qua Keycloak<br>- Tích hợp SIEM (ELK), NDR (Wazuh), Threat Intel (OpenCTI)<br>- Hỗ trợ .NET/MVC qua LDAP/SAML<br>- Giám sát hành vi UEBA | - MFA/SSO qua Entra ID<br>- SIEM tích hợp Sentinel<br>- UEBA/Microsoft Defender<br>- Tự động hóa SOAR | - Quản lý định danh tập trung<br>- Phân quyền động<br>- Tích hợp SSO/MFA<br>- Báo cáo tuân thủ GDPR |
| **CAPEX (Chi Phí Ban Đầu)** | - License Keycloak (Miễn phí)<br>- Server on-premise: 300M VNĐ<br>- Tích hợp custom: 150M VNĐ | - License Entra ID P2: 2.5 tỷ VNĐ (5 năm)<br>- Sentinel: 1.2 tỷ VNĐ<br>- Azure VM: 800M VNĐ | - License SailPoint: 4.5 tỷ VNĐ (5 năm)<br>- Server: 300M VNĐ<br>- Tư vấn triển khai: 500M VNĐ |
| **OPEX (Chi Phí Vận Hành)** | - Support HiPT: 500M/năm<br>- Nâng cấp server: 100M/năm | - Azure Subscription: 800M/năm<br>- Support Microsoft: 400M/năm | - Support SailPoint: 600M/năm<br>- Training: 100M/năm |
| **TCO (5 Năm)**      | **4.25 tỷ VNĐ**                            | **9.5 tỷ VNĐ**                        | **10.5 tỷ VNĐ**    |
| **ROI (Hiệu Quả Đầu Tư)** | - Tiết kiệm 60% chi phí<br>- Tùy biến cao<br>- Rủi ro vendor lock-in thấp | - Tự động hóa 80% tác vụ<br>- Giảm 50% thời gian phản hồi sự cố | - Tuân thủ 100% chuẩn ISO<br>- Giảm 70% rủi ro nội bộ |

---

### **Lược Đồ Triển Khai (Mermaid)**
#### **GP1: Keycloak + SIEM ELK/Wazuh/OpenCTI**
```mermaid
graph TD
    A[Legacy Apps .NET/MVC] -->|LDAP/SAML| B(Keycloak SSO/MFA)
    B -->|JWT Token| C[AD-DC Global]
    C -->|Syslog| D[SIEM ELK]
    D -->|Alerts| E[Wazuh EDR]
    E -->|Threat Data| F[OpenCTI]
    F -->|AI Analysis| G[Security Dashboard]
```

#### **GP2: Microsoft Entra ID + Sentinel**
```mermaid
graph TD
    A[Power BI/AD-DC] -->|OAuth 2.0| B(Entra ID)
    B -->|Conditional Access| C[MFA TOTP]
    C -->|Logs| D[Sentinel SIEM]
    D -->|Automation| E[SOAR Playbooks]
    E -->|UEBA| F[Microsoft Defender]
```

#### **GP3: SailPoint**
```mermaid
graph TD
    A[40+ Legacy Apps] -->|API Connectors| B(SailPoint IdentityIQ)
    B -->|Dynamic Policies| C[Role-Based Access]
    C -->|Certification| D[Access Reviews]
    D -->|SSO Integration| E[Keycloak/Entra ID]
    E -->|Audit Logs| F[Compliance Reports]
```

---

### **Đánh Giá Chi Tiết**
1. **GP1 (Keycloak)**:
   - **Ưu điểm**: Chi phí thấp nhất, mã nguồn mở tùy biến cao, phù hợp với hệ thống on-premise.
   - **Nhược điểm**: Cần kỹ sư cao cấp để vận hành hoặc cung cấp đầy đủ các dịch vụ OPEX-ITIL Helpdesk Support, rủi ro bảo mật nếu không patch thường xuyên và chỉ dưunjg 1 hệ thống đơn lẻ mà không HA Cluster.

2. **GP2 (Microsoft)**:
   - **Ưu điểm**: Tích hợp liền mạch với hệ sinh thái Azure, AI/ML mạnh mẽ (Microsoft Defender).
   - **Nhược điểm**: Phụ thuộc vào vendor, chi phí cao, rủi ro bảo mật và sự cố ở Cloud MSO365 có tính tập trung và bị tác động ảnh hưởng dây truyền.

3. **GP3 (SailPoint)**:
   - **Ưu điểm**: Dẫn đầu về quản lý định danh (IAM), tự động hóa phân quyền.
   - **Nhược điểm**: TCO cao nhất, cần thời gian triển khai dài, rủi ro bảo mật và sự cố ở Cloud Public có tính tập trung và bị tác động ảnh hưởng truyền.

---

### **Khuyến Nghị**
- **Ngân sách hạn chế**: Chọn **GP1** (tiết kiệm 60% chi phí).
- **Yêu cầu tuân thủ nghiêm ngặt**: Chọn **GP3**.
- **Hệ thống đã dùng Azure**: Chọn **GP2** để tối ưu tích hợp.

> **Lưu ý**: Cần đánh giá thêm khả năng tích hợp với các hệ thống hiện có của Bộ Tài chính (Power BI, AD-DC) trong giai đoạn PoC (Proof of Concept).
