SELECT 
    ROW_NUMBER() OVER(ORDER BY P.NGAY_PHIEU DESC) AS N'STT', -- 【序号】 按时间倒序生成的行号
    P.SOTK AS N'Số TK nhập',                  -- 【进口报关单号】
    P.NGAY_DK AS N'Ngày TK',                  -- 【报关日期】
    P.SO_HD AS N'Số hợp đồng',                -- 【合同号】
    P.NGAY_HD AS N'Ngày hợp đồng',            -- 【合同日期】
    P.SO_CHUNG_TU AS N'Chứng từ nội bộ',      -- 【内部凭证号】
    P.TEN_NGUOI_GIAO_HANG AS N'Người giao hàng', -- 【交货人/供应商】
    P.TONG_SO_KIEN AS N'Tổng số kiện',        -- 【总件数/箱数】
    P.SO_PHIEU AS N'Số phiếu',                -- 【入库单号】
    P.NGAY_PHIEU AS N'Ngày nhập kho',         -- 【实际入库日期】
    H.MA_SP AS N'Mã hàng',                    -- 【料号】
    H.TEN_SP AS N'Tên hàng',                  -- 【品名】
    H.MA_NUOC AS N'Xuất xứ',                  -- 【原产地】
    H.SO_LUONG AS N'Lượng',                   -- 【入库数量】
    H.MA_DVT AS N'Đơn vị tính',               -- 【计量单位】
    H.TRONG_LUONG_GW AS N'Trọng lượng GW',    -- 【毛重】 (Gross Weight)
    H.TRONG_LUONG_NW AS N'Trọng lượng NW',    -- 【净重】 (Net Weight)
    H.TRI_GIA AS N'Trị Giá',                  -- 【总价值】
    H.SO_QUAN_LY AS N'Số quản lý NB',         -- 【内部管理编号】
    H.SO_CONT AS N'Số container',             -- 【集装箱号/柜号】
    C.SO_SEAL_HQ AS N'Số chì HQ',             -- 【海关铅封号】 (通过 DCONTAINER 表关联)
    P.GHI_CHU AS N'Ghi chú',                  -- 【表头备注】
    H.GHI_CHU AS N'Ghi chú hàng'              -- 【明细行备注】
FROM 
    ECUS5_KNQ.dbo.DPHIEU P
INNER JOIN 
    ECUS5_KNQ.dbo.DPHIEU_HANG H ON P.DPHIEUID = H.DPHIEUID
LEFT JOIN 
    ECUS5_KNQ.dbo.DCONTAINER C ON P.DPHIEUID = C.DPHIEUID AND H.SO_CONT = C.SO_CONT
WHERE 
    P._XORN = 'N'                             -- 【过滤条件】 仅筛选入库单 (N = Nhập)
    AND ISNULL(H.IS_HUY, 0) = 0               -- 排除已作废的明细
    AND ISNULL(P.HUY_TRANG_THAI, 0) = 0;      -- 排除已作废的单头