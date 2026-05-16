SELECT 
    -- 1. 基础信息格式化
    ROW_NUMBER() OVER (ORDER BY P.NGAY_PHIEU DESC)  AS N'STT',
    LTRIM(RTRIM(REPLACE(CAST(P.SOTK AS VARCHAR(50)), '.0', ''))) AS N'Số TK nhập',
    CONVERT(VARCHAR(10), P.NGAY_DK, 103)            AS N'Ngày TK',
    P.SO_PHIEU                                      AS N'Số PNK',
    CONVERT(VARCHAR(10), P.NGAY_PHIEU, 103)         AS N'Ngày NK',
    P.SO_HD                                         AS N'Số hợp đồng',
    CONVERT(VARCHAR(10), P.NGAY_HD, 103)            AS N'Ngày hợp đồng',
    H.MA_SP                                         AS N'Mã hàng',
    H.TEN_SP                                        AS N'Tên hàng',

    -- 2. 商品标识码生成
    ISNULL(NULLIF(LTRIM(RTRIM(H.DINH_DANH_HANG_HOA)), ''),
           RIGHT(CAST(YEAR(ISNULL(P.NGAY_DK, P.NGAY_PHIEU)) AS VARCHAR(4)), 2)
           + LTRIM(RTRIM(REPLACE(CAST(P.SOTK AS VARCHAR(50)), '.0', '')))
           + '-'
           + RIGHT('00' + CAST(ISNULL(H.STTHANG, 1) AS VARCHAR(10)), 2)
    )                                               AS N'Định danh hàng hóa',

    -- 3. 元数据抓取 (产地、HS、单价) - 使用 APPLY 物理隔离，杜绝行爆炸
    M.MA_NUOC AS N'Xuất xứ',
    M.MA_HS AS N'Mã HS',
    H.SO_LUONG AS N'Lượng',
    M.DON_GIA AS N'Đơn giá',
    M.MA_DVT AS N'Đơn vị tính',

    -- 4. 实时库存核销 (核心修复：只有已报关的出库才扣减)
    ISNULL(X.LUONG_XUAT, 0)                         AS N'Lượng xuất',
    (H.SO_LUONG - ISNULL(X.LUONG_XUAT, 0))          AS N'SL Tồn',
    ((H.SO_LUONG - ISNULL(X.LUONG_XUAT, 0)) * M.DON_GIA) AS N'Trị Giá Tồn',
    
    P.MA_NT AS N'Mã NT',
    CONVERT(VARCHAR(10), P.NGAY_PHIEU, 103)         AS N'Ngày nhập',
    CONVERT(VARCHAR(10), X.NGAY_XUAT_CUOI, 103)     AS N'Ngày xuất',
    DATEDIFF(day, P.NGAY_PHIEU, GETDATE())          AS N'Số ngày tồn',
    H.GHI_CHU AS N'Ghi chú'

FROM ECUS5_KNQ.dbo.DPHIEU P
INNER JOIN ECUS5_KNQ.dbo.DPHIEU_HANG H ON P.DPHIEUID = H.DPHIEUID

-- 【主数据抓取】
OUTER APPLY (
    SELECT TOP 1 
        COALESCE(NULLIF(H.MA_NUOC, ''), NULLIF(HD.MA_NUOC, ''), NULLIF(SP.MA_NUOC, ''), 'VN') AS MA_NUOC,
        COALESCE(NULLIF(H.MA_HS, ''), NULLIF(HD.MA_HS, ''), NULLIF(SP.MA_HS, '')) AS MA_HS,
        COALESCE(NULLIF(H.MA_DVT, ''), NULLIF(HD.MA_DVT, ''), NULLIF(SP.MA_DVT, '')) AS MA_DVT,
        COALESCE(H.DON_GIA, HD.DON_GIA, 0) AS DON_GIA
    FROM (SELECT 1 as d) d_table
    LEFT JOIN ECUS5_KNQ.dbo.DHOPDONG_HANG HD ON P.DHOPDONGID = HD.DHOPDONGID AND H.MA_SP = HD.MA_SP
    LEFT JOIN ECUS5_KNQ.dbo.SSANPHAM SP ON H.MA_SP = SP.MA_SP AND SP.MA_KNQ = P.MA_KNQ
) M

-- 【出库核销：解决 353 vs 208 GAP 的关键】
OUTER APPLY (
    SELECT 
        SUM(ISNULL(HX.SO_LUONG, 0)) AS LUONG_XUAT,
        MAX(PX.NGAY_XUAT) AS NGAY_XUAT_CUOI
    FROM ECUS5_KNQ.dbo.DPHIEU_HANG HX
    INNER JOIN ECUS5_KNQ.dbo.DPHIEU PX ON HX.DPHIEUID = PX.DPHIEUID
    WHERE PX._XORN = 'X' 
      AND HX.MA_SP = H.MA_SP
      AND ISNULL(HX.IS_HUY, 0) = 0 
      AND ISNULL(PX.HUY_TRANG_THAI, 0) = 0
      -- 核心：只有已报关或已过账的出库才从库存中扣除
      AND (PX.MESSAGEID IS NOT NULL OR PX.NGAY_DK IS NOT NULL)
      AND (
          (HX.SOTK_N = P.SOTK AND HX.STTHANG_N = H.STTHANG AND P.SOTK IS NOT NULL)
          OR (HX.SO_PHIEU_N = P.SO_PHIEU AND HX.MA_SP = H.MA_SP AND P.SO_PHIEU IS NOT NULL)
      )
) X

WHERE 
    P._XORN = 'N'                             -- 仅入库
    AND P.MA_KNQ = 'VNNSL'                    -- 锁定 VNNSL 仓库
    AND ISNULL(P.HUY_TRANG_THAI, 0) = 0       -- 排除单头作废
    AND ISNULL(H.IS_HUY, 0) = 0               -- 排除行项作废
    
    -- 【对齐 14242 行的终极条件】
    -- 1. 强制 12 位纯数字报关单，排除 1.5 万行草稿噪声
    AND LTRIM(RTRIM(REPLACE(CAST(P.SOTK AS VARCHAR(50)), '.0', ''))) LIKE '[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]'
    
    -- 2. 状态过滤：排除明确的草稿状态 (T/0/1)
    AND ISNULL(P.TRANG_THAI, '') NOT IN ('T', '0', '1', 'H')
    
    -- 3. 生效条件：找回丢失的 366 行退货单
    AND (P.MESSAGEID IS NOT NULL OR P.NGAY_DK IS NOT NULL OR P.SO_PHIEU LIKE '%RH%')

    -- 4. 实时库存大于 0
    AND (H.SO_LUONG - ISNULL(X.LUONG_XUAT, 0)) > 0.001

ORDER BY P.NGAY_PHIEU DESC;