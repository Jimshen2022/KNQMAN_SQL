SELECT 
    ROW_NUMBER() OVER (ORDER BY P.NGAY_PHIEU DESC)  AS N'STT',
    LTRIM(RTRIM(REPLACE(CAST(P.SOTK AS VARCHAR(50)), '.0', ''))) AS N'Số TK nhập',
    CONVERT(VARCHAR(10), P.NGAY_DK, 103)            AS N'Ngày TK',
    P.SO_PHIEU                                      AS N'Số PNK',
    CONVERT(VARCHAR(10), P.NGAY_PHIEU, 103)         AS N'Ngày NK',
    P.SO_HD                                         AS N'Số hợp đồng',
    CONVERT(VARCHAR(10), P.NGAY_HD, 103)            AS N'Ngày hợp đồng',
    H.MA_SP                                         AS N'Mã hàng',
    H.TEN_SP                                        AS N'Tên hàng',

    ISNULL(NULLIF(LTRIM(RTRIM(H.DINH_DANH_HANG_HOA)), ''),
           RIGHT(CAST(YEAR(ISNULL(P.NGAY_DK, P.NGAY_PHIEU)) AS VARCHAR(4)), 2)
           + LTRIM(RTRIM(REPLACE(CAST(P.SOTK AS VARCHAR(50)), '.0', '')))
           + '-'
           + RIGHT('00' + CAST(ISNULL(H.STTHANG, 1) AS VARCHAR(10)), 2)
    )                                               AS N'Định danh hàng hóa',

    M.MA_NUOC AS N'Xuất xứ',
    M.MA_HS AS N'Mã HS',
    H.SO_LUONG AS N'Lượng',
    M.DON_GIA AS N'Đơn giá',
    M.MA_DVT AS N'Đơn vị tính',

    -- 实时出库核销 (包含销毁和转让)
    ISNULL(X.LUONG_XUAT, 0)                         AS N'Lượng xuất',
    ROUND((H.SO_LUONG - ISNULL(X.LUONG_XUAT, 0)), 3) AS N'SL Tồn',
    ROUND(((H.SO_LUONG - ISNULL(X.LUONG_XUAT, 0)) * M.DON_GIA), 2) AS N'Trị Giá Tồn',
    
    P.MA_NT AS N'Mã NT',
    CONVERT(VARCHAR(10), P.NGAY_PHIEU, 103)         AS N'Ngày nhập',
    CONVERT(VARCHAR(10), X.NGAY_XUAT_CUOI, 103)     AS N'Ngày xuất',
    DATEDIFF(day, P.NGAY_PHIEU, GETDATE())          AS N'Số ngày tồn',
    H.GHI_CHU AS N'Ghi chú'

FROM ECUS5_KNQ.dbo.DPHIEU P
INNER JOIN ECUS5_KNQ.dbo.DPHIEU_HANG H ON P.DPHIEUID = H.DPHIEUID

-- 【主数据关联】
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

-- 🚀 【终极出库核销：综合 正常出库 + 销毁 + 转让】
OUTER APPLY (
    SELECT 
        SUM(ISNULL(EXPORT_QTY, 0)) AS LUONG_XUAT,
        MAX(NGAY_XUAT) AS NGAY_XUAT_CUOI
    FROM (
        -- 1. 正常出库单 (Phiếu Xuất)
        SELECT HX.SO_LUONG AS EXPORT_QTY, PX.NGAY_PHIEU AS NGAY_XUAT
        FROM ECUS5_KNQ.dbo.DPHIEU_HANG HX
        INNER JOIN ECUS5_KNQ.dbo.DPHIEU PX ON HX.DPHIEUID = PX.DPHIEUID
        WHERE PX._XORN = 'X' 
          AND PX.MA_KNQ = 'VNNSL'
          AND ISNULL(HX.IS_HUY, 0) = 0 
          AND ISNULL(PX.MA_NGUON, '') <> 'X4' -- 防内部循环重算
          AND PX.TRANG_THAI IN ('E', 'D', 'T') 
          AND ((PX.PB_PHIEU = 'CT' AND PX.DPHIEUID_NEXT IS NULL) OR (PX.PB_PHIEU = 'SU' AND PX.DPHIEUID_PREV IS NOT NULL))
          AND PX.TYPE = P.TYPE
          AND HX.SO_PHIEU_N = P.SO_PHIEU
          AND ISNULL(HX.DINH_DANH_HANG_HOA, '') = ISNULL(H.DINH_DANH_HANG_HOA, '')

        UNION ALL

        -- 2. 报废/销毁记录 (Tiêu hủy)
        SELECT TH_CT.SO_LUONG AS EXPORT_QTY, TH.NGAY_PHIEU AS NGAY_XUAT
        FROM ECUS5_KNQ.dbo.DTIEUHUY_CT TH_CT
        INNER JOIN ECUS5_KNQ.dbo.DTIEUHUY TH ON TH_CT.DTIEUHUYID = TH.DTIEUHUYID
        WHERE TH.MA_KNQ = 'VNNSL' 
          AND TH.TRANG_THAI = 1
          AND TH_CT.SO_PHIEU_N = P.SO_PHIEU
          AND ISNULL(TH_CT.DINH_DANH_HANG_HOA, '') = ISNULL(H.DINH_DANH_HANG_HOA, '')

        UNION ALL

        -- 3. 产权转移/跨合同转出 (Chuyển quyền)
        SELECT VB_H.SO_LUONG AS EXPORT_QTY, VB.NGAY_CHUYEN_QUYEN AS NGAY_XUAT
        FROM ECUS5_KNQ.dbo.DVANBAN_HANG VB_H
        INNER JOIN ECUS5_KNQ.dbo.DVANBAN VB ON VB_H.DVANBANID = VB.DVANBANID
        WHERE VB.TRANG_THAI = '2'
          AND VB_H.SO_PHIEU_N = P.SO_PHIEU
          AND ISNULL(VB_H.DINH_DANH_HANG_HOA, '') = ISNULL(H.DINH_DANH_HANG_HOA, '')
    ) AS EXPORT_DATA
) X

WHERE 
    P._XORN = 'N'                             
    AND P.MA_KNQ = 'VNNSL'                    
    AND ISNULL(H.IS_HUY, 0) = 0               
    
    -- 官方入库生效状态
    AND P.TRANG_THAI IN ('E', 'D', 'T') 
    AND ((P.PB_PHIEU = 'CT' AND P.DPHIEUID_NEXT IS NULL) OR (P.PB_PHIEU = 'SU' AND P.DPHIEUID_PREV IS NOT NULL))

    -- 【入库防重机制】：排除掉已经被“掏箱”分拆的原始集装箱
    AND (
        (P.TYPE = 2) -- 散货正常显示
        OR 
        (P.TYPE = 1 AND EXISTS ( 
            SELECT 1 FROM ECUS5_KNQ.dbo.DCONTAINER DC 
            WHERE DC.DPHIEUID = P.DPHIEUID AND DC.SO_CONT = H.SO_CONT AND ISNULL(DC.IS_HUY, 0) = 0 AND DC.IS_RUTHANG = 0
        ) AND NOT EXISTS ( -- 排除在 DRUTHANG 中已挂号的掏空箱
            SELECT 1 FROM ECUS5_KNQ.dbo.DRUTHANG DR 
            INNER JOIN ECUS5_KNQ.dbo.DRUTHANG_CT DR_CT ON DR.DRUTHANGID = DR_CT.DRUTHANGID
            WHERE DR.DPHIEUID = P.DPHIEUID AND DR.SO_CONT = H.SO_CONT AND DR.MA_KNQ = 'VNNSL' AND DR.TRANG_THAI = 2
        ))
    )

    -- 只有结存量 > 0 的才算库存 (那 91 行将被这里完美拦截)
    AND ROUND((H.SO_LUONG - ISNULL(X.LUONG_XUAT, 0)), 3) > 0.001

ORDER BY P.NGAY_PHIEU DESC;