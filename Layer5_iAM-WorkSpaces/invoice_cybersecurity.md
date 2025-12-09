# Cybersecurity Quoting Requirements for Finance Ministry
>>> Hãy viết tóm tắt nhưng đầy đủ các hạng mục cần Báo Giá Thiết Bị và Phần Mềm An Ninh Mạng Bộ Tài Chính trong cả phụ lục 1, phụ lục 2



Chắc chắn rồi. Dưới đây là tóm tắt đầy đủ các hạng mục cần báo giá, được tổng hợp từ cả Phụ lục I (Mẫu Bảng báo giá) và Phụ lục II (Yêu cầu chi tiết kỹ thuật) của Công văn.

---

Dựa trên Công văn số /CNTT-ATANM, các nhà thầu cần gửi báo giá cho **11 hạng mục hệ thống an ninh mạng** sau đây. Báo giá cần bao gồm chi phí cho thiết bị, bản quyền phần mềm và các dịch vụ liên quan để triển khai và vận hành trong thời hạn 05 năm.

**Tóm tắt các hạng mục cần báo giá:**

1.  **Hệ thống xác thực đa nhân tố (MFA):**
    *   **Mục đích:** Tăng cường bảo mật đăng nhập cho các ứng dụng.
    *   **Phạm vi:** Triển khai cho các ứng dụng tại Trung tâm dữ liệu của Bộ Tài chính.
    *   **Yêu cầu chính:** Hỗ trợ xác thực cho web, VPN, SSH, RDP...; Hỗ trợ nhiều phương thức như Mobile App (vân tay, khuôn mặt), FIDO2, Security Key, Email...

2.  **Hệ thống quản lý định danh và xác thực điện tử tập trung (IAM):**
    *   **Mục đích:** Quản lý tập trung tài khoản và quyền truy cập người dùng trên nhiều hệ thống.
    *   **Phạm vi:** Triển khai cho các ứng dụng tại Trung tâm dữ liệu của Bộ Tài chính.
    *   **Yêu cầu chính:** Quản lý vòng đời tài khoản, quy trình yêu cầu và phê duyệt quyền, rà soát quyền truy cập định kỳ, phân tách quyền (SOD).

3.  **Hệ thống phòng chống thất thoát dữ liệu (DLP):**
    *   **Mục đích:** Ngăn chặn rò rỉ dữ liệu nhạy cảm.
    *   **Phạm vi:** Bảo vệ **2.300 máy trạm và máy chủ**.
    *   **Yêu cầu chính:** Kiểm soát dữ liệu qua email, web, USB; Hỗ trợ mã hóa dữ liệu; Sử dụng máy học để phát hiện bất thường.

4.  **Hệ thống Giám sát an toàn, an ninh mạng (SOC):**
    *   **Mục đích:** Xây dựng Trung tâm Giám sát và Điều hành An ninh mạng (SOC) 24/7.
    *   **Phạm vi:** Trang bị cơ sở hạ tầng và các công cụ giám sát cho Bộ Tài chính và các đơn vị trực thuộc.
    *   **Yêu cầu chính:**
        *   **a) Trang thiết bị SOC:** Bàn điều khiển, màn hình lớn, máy tính, hệ thống mạng, nguồn điện...
        *   **b) Phần mềm & Dịch vụ:** Hệ thống phát hiện xâm nhập (NIDS/EDR), quản lý sự kiện (SIEM), thông tin mối đe dọa (Threat Intelligence) và dịch vụ giám sát 24/7.

5.  **Hệ thống quản trị nguy cơ và phòng chống tấn công chủ động:**
    *   **Mục đích:** Quản lý lỗ hổng, điểm yếu và phòng chống tấn công có chủ đích.
    *   **Phạm vi:** Quản lý cho các hệ thống thông tin do Cục CNTT quản lý.
    *   **Yêu cầu chính:** Tổng hợp thông tin lỗ hổng, theo dõi lịch sử đánh giá, tấn công thử nghiệm, theo dõi quá trình khắc phục.

6.  **Hệ thống quản lý truy cập mạng (NAC):**
    *   **Mục đích:** Kiểm soát truy cập vào mạng nội bộ (LAN, WiFi).
    *   **Phạm vi:** Kiểm soát truy cập cho **2.300 máy chủ, máy trạm** tại Văn phòng Bộ Tài chính.
    *   **Yêu cầu chính:** Hỗ trợ IEEE 802.1X, tích hợp với AD, nhận diện và phân loại thiết bị, tự động phân vùng mạng (VLAN).

7.  **Hệ thống kiểm soát truy cập không tin cậy (ZTNA):**
    *   **Mục đích:** Bảo vệ truy cập từ xa theo mô hình Zero Trust.
    *   **Phạm vi:** License cho **5.000 kết nối (Endpoint)**.
    *   **Yêu cầu chính:** Xác thực danh tính và thiết bị, phân quyền truy cập tối thiểu, ngăn di chuyển ngang trong mạng, giám sát liên tục.

8.  **Phần mềm nội bộ quản lý an ninh mạng:**
    *   **Mục đích:** Quản lý thống nhất công tác an ninh mạng cho toàn ngành Tài chính.
    *   **Phạm vi:** Toàn ngành Tài chính.
    *   **Yêu cầu chính:** Quản lý danh mục hệ thống, thiết bị; Quản lý nhiệm vụ an ninh; Báo cáo tuân thủ; Quản lý văn bản, chỉ đạo.

9.  **Bộ máy tính và công cụ ứng cứu, điều tra số:**
    *   **Mục đích:** Trang bị công cụ cho đội ngũ ứng cứu sự cố và điều tra số.
    *   **Phạm vi:** Trang bị **02 bộ máy tính và công cụ**.
    *   **Yêu cầu chính:** Bao gồm công cụ rà quét lỗ hổng (VA/VM), điều tra số (Digital Forensics), phân tích mã độc, truy vết nhật ký.

10. **Hệ thống quét bảo mật tệp tin tải lên máy chủ:**
    *   **Mục đích:** Phát hiện mã độc và các thay đổi bất thường trong tệp tin được tải lên máy chủ.
    *   **Phạm vi:** License cho **tối thiểu 20 ứng dụng**.
    *   **Yêu cầu chính:** Quét mã độc theo thời gian thực, phân tích sâu nội dung tệp, tích hợp qua API, tạo báo cáo chi tiết.

11. **Hệ thống bảo mật cho thiết bị di động (MDM):**
    *   **Mục đích:** Quản lý và bảo mật các thiết bị di động của cán bộ.
    *   **Phạm vi:** Phần mềm quản lý cho **300 người dùng**.
    *   **Yêu cầu chính:** Quản lý vòng đời thiết bị, mã hóa dữ liệu, quản lý ứng dụng, kiểm soát truy cập, xóa dữ liệu từ xa.
