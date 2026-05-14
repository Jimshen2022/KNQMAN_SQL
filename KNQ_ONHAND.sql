SELECT 
    -- 1. 格式化输出：STT 序号及日期格式对齐客户端 (DD/MM/YYYY)
    ROW_NUMBER() OVER (ORDER BY P.NGAY_PHIEU DESC)  AS N'STT',
    LTRIM(RTRIM(CAST(P.SOTK AS VARCHAR(50))))       AS N'Số TK nhập',
    CONVERT(VARCHAR(10), P.NGAY_DK, 103)            AS N'Ngày TK',
    P.SO_PHIEU                                      AS N'Số PNK',
    CONVERT(VARCHAR(10), P.NGAY_PHIEU, 103)         AS N'Ngày NK',
    P.SO_HD                                         AS N'Số hợp đồng',
    CONVERT(VARCHAR(10), P.NGAY_HD, 103)            AS N'Ngày hợp đồng',
    H.MA_SP                                         AS N'Mã hàng',
    H.TEN_SP                                        AS N'Tên hàng',

    -- 2. 商品标识码：动态生成逻辑
    ISNULL(
        NULLIF(LTRIM(RTRIM(H.DINH_DANH_HANG_HOA)), ''),
        RIGHT(CAST(YEAR(ISNULL(P.NGAY_DK, P.NGAY_PHIEU)) AS VARCHAR(4)), 2)
        + ISNULL(CAST(P.SOTK AS VARCHAR(50)), '')
        + '-'
        + RIGHT('00' + CAST(ISNULL(H.STTHANG, 1) AS VARCHAR(10)), 2)
    )                                               AS N'Định danh hàng hóa',

    -- 3. 产地与单价：借鉴 Claude 的 TOP 1 逻辑，彻底杜绝数据翻倍
    COALESCE(NULLIF(H.MA_NUOC,''), NULLIF(HD.MA_NUOC,''), NULLIF(SP.MA_NUOC,'')) AS N'Xuất xứ',
    COALESCE(NULLIF(H.MA_HS,''),   NULLIF(HD.MA_HS,''),   NULLIF(SP.MA_HS,''))   AS N'Mã HS',
    H.SO_LUONG                                      AS N'Lượng',
    COALESCE(H.DON_GIA, HD.DON_GIA, 0)              AS N'Đơn giá',
    COALESCE(NULLIF(H.MA_DVT,''), NULLIF(HD.MA_DVT,''), NULLIF(SP.MA_DVT,''))    AS N'Đơn vị tính',

    -- 4. 结存计算：精准扣除已出库数量
    ISNULL(X.LUONG_XUAT, 0)                         AS N'Lượng xuất',
    (H.SO_LUONG - ISNULL(X.LUONG_XUAT, 0))          AS N'SL Tồn',
    ((H.SO_LUONG - ISNULL(X.LUONG_XUAT, 0)) * COALESCE(H.DON_GIA, HD.DON_GIA, 0)) AS N'Trị Giá Tồn',
    P.MA_NT                                         AS N'Mã NT',
    CONVERT(VARCHAR(10), P.NGAY_PHIEU, 103)         AS N'Ngày nhập',
    CONVERT(VARCHAR(10), X.NGAY_XUAT_CUOI, 103)     AS N'Ngày xuất',
    DATEDIFF(day, P.NGAY_PHIEU, GETDATE())          AS N'Số ngày tồn',
    H.GHI_CHU                                       AS N'Ghi chú'

FROM ECUS5_KNQ.dbo.DPHIEU P
INNER JOIN ECUS5_KNQ.dbo.DPHIEU_HANG H ON P.DPHIEUID = H.DPHIEUID

-- 使用 OUTER APPLY 取合同第一行，防止因合同重复导致的 14180 翻倍为 29754
OUTER APPLY (
    SELECT TOP 1
        HD2.MA_NUOC, HD2.MA_HS, HD2.MA_DVT, HD2.DON_GIA
    FROM ECUS5_KNQ.dbo.DHOPDONG_HANG HD2
    WHERE HD2.DHOPDONGID = P.DHOPDONGID
      AND HD2.MA_SP = H.MA_SP
) HD

LEFT JOIN ECUS5_KNQ.dbo.SSANPHAM SP ON H.MA_SP = SP.MA_SP AND SP.MA_KNQ = P.MA_KNQ

-- 出库汇总逻辑
OUTER APPLY (
    SELECT 
        SUM(ISNULL(HX.SO_LUONG, 0))  AS LUONG_XUAT,
        MAX(PX.NGAY_XUAT)            AS NGAY_XUAT_CUOI
    FROM ECUS5_KNQ.dbo.DPHIEU_HANG HX
    INNER JOIN ECUS5_KNQ.dbo.DPHIEU PX ON HX.DPHIEUID = PX.DPHIEUID
    WHERE PX._XORN = 'X' 
      AND HX.MA_SP = H.MA_SP
      AND ISNULL(HX.IS_HUY, 0) = 0 
      AND ISNULL(PX.HUY_TRANG_THAI, 0) = 0
      AND (
          (HX.SOTK_N = P.SOTK AND HX.STTHANG_N = H.STTHANG AND P.SOTK <> '')
          OR (HX.SO_PHIEU_N = P.SO_PHIEU AND HX.MA_SP = H.MA_SP AND P.SO_PHIEU <> '')
      )
) X

WHERE 
    P._XORN = 'N'                             -- 仅入库
    AND P.MA_KNQ = 'VNNSL'                    -- 仅看 VNNSL 仓库
    AND ISNULL(H.IS_HUY, 0) = 0               -- 排除作废
    AND ISNULL(P.HUY_TRANG_THAI, 0) = 0       -- 排除作废单头

    -- 【第一性原理：针对 14180 行目标报表的终极过滤】
    -- 1. 必须有海关通讯流水号（代表已正式申报，排除本地草稿）
    AND P.MESSAGEID IS NOT NULL 
    -- 2. 报关单号必须是标准的 12 位纯数字（排除临时单、合同占位符）
    AND LTRIM(RTRIM(CAST(P.SOTK AS VARCHAR(50)))) LIKE '[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]'
    
    -- 3. 库存余量大于 0
    AND (H.SO_LUONG - ISNULL(X.LUONG_XUAT, 0)) > 0.001

ORDER BY P.NGAY_PHIEU DESC;