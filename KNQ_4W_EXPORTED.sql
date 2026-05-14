SELECT 
    ROW_NUMBER() OVER(ORDER BY P.NGAY_PHIEU DESC) AS N'STT', -- 【序号】
    H.SOTK_N AS N'Số TK nhập',                -- 【原进口报关单号】 该笔出库对应的原始进口单号 (海关核销关键字段)
    PN.NGAY_DK AS N'Ngày TK',                 -- 【原报关日期】
    P.SO_HD AS N'Số hợp đồng',                -- 【合同号】
    P.NGAY_HD AS N'Ngày hợp đồng',            -- 【合同日期】
    P.SO_PHIEU AS N'Số phiếu',                -- 【出库单号】
    P.NGAY_PHIEU AS N'Ngày phiếu',            -- 【出库制单日期】
    P.SO_CHUNG_TU AS N'Chứng từ nội bộ',      -- 【内部凭证号】
    P.TONG_SO_KIEN AS N'Tổng số kiện',        -- 【总件数/箱数】
    P.TEN_NGUOI_NHAN_HANG AS N'Người nhận hàng', -- 【收货人/客户】
    P.SOTK AS N'Số tờ khai/CT',               -- 【出口报关单号】
    P.NGAY_DK AS N'Ngày tờ khai',             -- 【出口报关日期】
    P.NGAY_XUAT AS N'Ngày xuất kho',          -- 【实际出库日期】
    PN.NGAY_PHIEU AS N'Ngày nhập',            -- 【原入库日期】 用于追溯
    DATEDIFF(day, PN.NGAY_PHIEU, P.NGAY_XUAT) AS N'Số ngày tồn', -- 【出库时的库龄】 货物在仓库里待了多少天后被发走
    H.MA_SP AS N'Mã hàng',                    -- 【料号】
    H.TEN_SP AS N'Tên hàng',                  -- 【品名】
    H.MA_NUOC AS N'Xuất xứ',                  -- 【原产地】
    H.SO_LUONG AS N'Lượng',                   -- 【出库数量】
    H.MA_DVT AS N'Đơn vị tính',               -- 【计量单位】
    H.TRONG_LUONG_GW AS N'Trọng lượng GW',    -- 【毛重】
    H.TRONG_LUONG_NW AS N'Trọng lượng NW',    -- 【净重】
    H.TRI_GIA AS N'Trị Giá',                  -- 【总价值】
    H.SO_QUAN_LY AS N'Số quản lý NB',         -- 【内部管理编号】
    H.SO_CONT AS N'Số container',             -- 【集装箱号/柜号】
    C.SO_SEAL_HQ AS N'Số chì HQ',             -- 【海关铅封号】
    P.GHI_CHU AS N'Ghi chú',                  -- 【表头备注】
    H.GHI_CHU AS N'Ghi chú hàng'              -- 【明细行备注】
FROM 
    ECUS5_KNQ.dbo.DPHIEU P
INNER JOIN 
    ECUS5_KNQ.dbo.DPHIEU_HANG H ON P.DPHIEUID = H.DPHIEUID
LEFT JOIN 
    ECUS5_KNQ.dbo.DPHIEU PN ON H.SO_PHIEU_N = PN.SO_PHIEU AND PN._XORN = 'N' -- 【自连接】 关联回原入库单获取入库时间
LEFT JOIN 
    ECUS5_KNQ.dbo.DCONTAINER C ON P.DPHIEUID = C.DPHIEUID AND H.SO_CONT = C.SO_CONT
WHERE 
    P._XORN = 'X'                             -- 【过滤条件】 仅筛选出库单 (X = Xuất)
    AND ISNULL(H.IS_HUY, 0) = 0
    AND ISNULL(P.HUY_TRANG_THAI, 0) = 0;