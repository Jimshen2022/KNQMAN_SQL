SELECT 
    ROW_NUMBER() OVER(ORDER BY P.NGAY_PHIEU DESC) AS N'STT', 
    P.SOTK AS N'Số TK nhập', 
    P.NGAY_DK AS N'Ngày TK', 
    P.SO_HD AS N'Số hợp đồng', 
    P.NGAY_HD AS N'Ngày hợp đồng', 
    P.SO_CHUNG_TU AS N'Chứng từ nội bộ', 
    P.TEN_NGUOI_GIAO_HANG AS N'Người giao hàng', 
    P.TONG_SO_KIEN AS N'Tổng số kiện', 
    P.SO_PHIEU AS N'Số phiếu', 
    P.NGAY_PHIEU AS N'Ngày nhập kho', 
    H.MA_SP AS N'Mã hàng', 
    H.TEN_SP AS N'Tên hàng', 
    H.MA_NUOC AS N'Xuất xứ', 
    H.SO_LUONG AS N'Lượng', 
    H.MA_DVT AS N'Đơn vị tính', 
    H.TRONG_LUONG_GW AS N'Trọng lượng GW', 
    H.TRONG_LUONG_NW AS N'Trọng lượng NW', 
    H.TRI_GIA AS N'Trị Giá', 
    H.SO_QUAN_LY AS N'Số quản lý NB', 
    H.SO_CONT AS N'Số container', 
    C.SO_SEAL_HQ AS N'Số chì HQ', 
    P.GHI_CHU AS N'Ghi chú', 
    H.GHI_CHU AS N'Ghi chú hàng' 
FROM ECUS5_KNQ.dbo.DPHIEU P 
INNER JOIN ECUS5_KNQ.dbo.DPHIEU_HANG H ON P.DPHIEUID = H.DPHIEUID 
LEFT JOIN ECUS5_KNQ.dbo.DCONTAINER C ON P.DPHIEUID = C.DPHIEUID AND H.SO_CONT = C.SO_CONT 
WHERE P._XORN = 'N' 
AND ISNULL(H.IS_HUY, 0) = 0 
AND ISNULL(P.HUY_TRANG_THAI, 0) = 0;