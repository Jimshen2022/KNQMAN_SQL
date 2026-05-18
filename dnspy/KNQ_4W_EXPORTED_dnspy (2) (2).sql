-- ====================================================================
-- 终极版：ECUS5 保税仓货物出库明细流水账（KNQ_4W_EXPORTED）
-- （包含：自动溯源补全入库报关单/合同/入仓日期，并 100% 对齐导出 Excel 格式）
-- ====================================================================
SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

-- ========================================
-- 🔻 请在这里修改你的查询参数 🔻
-- ========================================
DECLARE @MaKNQ NVARCHAR(50) = 'VNNSL';          --【变量：保税仓代码】
DECLARE @StartDate DATETIME = '2026-01-01';     --【变量：出库开始日期】
DECLARE @EndDate DATETIME = '2026-05-17';       --【变量：出库结束日期】

-- --------------------------------------------------------------------
-- STEP 1: 提取所有【集装箱重箱（Type = 1）】的正式有效出库明细
-- --------------------------------------------------------------------
IF OBJECT_ID('tempdb..#XUAT') IS NOT NULL DROP TABLE #XUAT;

SELECT 
    CAST('' AS NVARCHAR(100)) AS CKEYS, 
    A.TYPE, A.SOTK AS SOTK_X, A.NGAY_DK AS NGAY_DK_X, A.SO_PHIEU, A.NGAY_PHIEU, A.DPHIEUID, A.DHOPDONGID, A.SO_HD, A.NGAY_HD, 
    MAX(A.SO_BBBG) AS SO_BBBG, MAX(A.SO_CHUNG_TU) AS SO_CHUNG_TU, MAX(A.TEN_NGUOI_NHAN_HANG) AS TEN_NGUOI_NHAN_HANG, 
    MAX(A.TONG_SO_KIEN) AS TONG_SO_KIEN, MAX(A.PHUONG_TIEN) AS PHUONG_TIEN, 
    B.SO_PHIEU_N, B.STTHANG_N, B.STTHANG, B.SO_TK, CAST(B.NGAY_DK AS DATE) AS NGAY_DK, B.MA_SP, B.DINH_DANH_HANG_HOA, B.SO_CONT,
    MAX(B.TEN_SP) AS TEN_SP, MAX(B.MA_NUOC) AS MA_NUOC, MAX(B.MA_HS) AS MA_HS, 
    SUM(B.SO_LUONG) AS SO_LUONG, 
    MAX(B.MA_DVT) AS MA_DVT, SUM(B.TRONG_LUONG_GW) AS TRONG_LUONG_GW, SUM(B.TRONG_LUONG_NW) AS TRONG_LUONG_NW, 
    SUM(B.TRI_GIA) AS TRI_GIA, MAX(B.VI_TRI_HANG) AS VI_TRI_HANG, MAX(I.TEN_DVT) AS TEN_DVT, MAX(T.TEN_CK) AS TEN_CK, 
    MAX(DF.SO_SEAL) AS SO_SEAL, 
    CAST('' AS NVARCHAR(250)) AS GHI_CHU, 
    MAX(B.GHI_CHU) AS GHI_CHU_HANG, 
    CAST(NULL AS DATE) AS NGAY_NHAP,
    CAST(NULL AS INT) AS SO_NGAY_TON,
    MAX(B.SO_QUAN_LY) AS SO_QUAN_LY 
INTO #XUAT 
FROM DPHIEU A WITH (NOLOCK)
INNER JOIN DPHIEU_HANG B WITH (NOLOCK) ON A.DPHIEUID = B.DPHIEUID AND ISNULL(B.IS_HUY, 0) = 0 
INNER JOIN DCONTAINER DF WITH (NOLOCK) ON DF.DPHIEUID = A.DPHIEUID AND DF.IS_RUTHANG = 0 AND DF.TINH_TRANG = 1 AND A.DRUTHANGID IS NULL 
LEFT JOIN SDVT I WITH (NOLOCK) ON B.MA_DVT = I.MA_DVT 
LEFT JOIN SCUAKHAU T WITH (NOLOCK) ON T.MA_CK = A.MA_CK_XUAT
WHERE A.MA_KNQ = @MaKNQ 
  AND A.TYPE = 1                                  
  AND A._XORN = 'X'                               
  AND A.MA_NGUON <> 'X4'                          
  AND A.TRANG_THAI = 'T' 
  AND ((A.PB_PHIEU = 'CT' AND A.DPHIEUID_NEXT IS NULL) OR (A.PB_PHIEU = 'SU' AND A.DPHIEUID_PREV IS NOT NULL))
  AND A.NGAY_PHIEU >= @StartDate 
  AND A.NGAY_PHIEU <= @EndDate
GROUP BY A.TYPE, A.SOTK, A.NGAY_DK, A.SO_PHIEU, A.NGAY_PHIEU, A.DPHIEUID, A.DHOPDONGID, A.SO_HD, A.NGAY_HD, 
         B.SO_PHIEU_N, B.STTHANG_N, B.STTHANG, B.SO_TK, CAST(B.NGAY_DK AS DATE), B.MA_SP, B.DINH_DANH_HANG_HOA, B.SO_CONT;

-- --------------------------------------------------------------------
-- STEP 2: 追加写入【普通散货 / 件货（Type = 2）】的生效出库流水
-- --------------------------------------------------------------------
INSERT INTO #XUAT 
SELECT CAST('' AS NVARCHAR(100)) AS CKEYS, A.TYPE, A.SOTK AS SOTK_X, A.NGAY_DK AS NGAY_DK_X, A.SO_PHIEU, A.NGAY_PHIEU, A.DPHIEUID, A.DHOPDONGID, A.SO_HD, A.NGAY_HD, MAX(A.SO_BBBG) SO_BBBG, MAX(A.SO_CHUNG_TU)SO_CHUNG_TU, MAX(A.TEN_NGUOI_NHAN_HANG) TEN_NGUOI_NHAN_HANG, MAX(A.TONG_SO_KIEN)TONG_SO_KIEN, MAX(A.PHUONG_TIEN) PHUONG_TIEN, B.SO_PHIEU_N, B.STTHANG_N, B.STTHANG, B.SO_TK,CAST(B.NGAY_DK AS DATE) AS NGAY_DK, B.MA_SP, B.DINH_DANH_HANG_HOA,B.SO_CONT, MAX(B.TEN_SP)TEN_SP,MAX(B.MA_NUOC)MA_NUOC,MAX(B.MA_HS)MA_HS,SUM(B.SO_LUONG)SO_LUONG,MAX(B.MA_DVT)MA_DVT,SUM(B.TRONG_LUONG_GW)TRONG_LUONG_GW,SUM(B.TRONG_LUONG_NW)TRONG_LUONG_NW,SUM(B.TRI_GIA)TRI_GIA,MAX(B.VI_TRI_HANG)VI_TRI_HANG,MAX(I.TEN_DVT)TEN_DVT,MAX(T.TEN_CK)TEN_CK,'' SO_SEAL, '' GHI_CHU, MAX(B.GHI_CHU) AS GHI_CHU_HANG, CAST (NULL AS DATE) NGAY_NHAP, CAST(NULL AS INT) AS SO_NGAY_TON, MAX(B.SO_QUAN_LY) SO_QUAN_LY 
FROM DPHIEU A WITH (NOLOCK)
INNER JOIN DPHIEU_HANG B WITH (NOLOCK) ON (A.DPHIEUID = B.DPHIEUID AND ISNULL(B.IS_HUY, 0) = 0) 
LEFT JOIN SDVT I WITH (NOLOCK) ON B.MA_DVT = I.MA_DVT 
LEFT JOIN SCUAKHAU T WITH (NOLOCK) ON T.MA_CK = A.MA_CK_XUAT
WHERE A.MA_KNQ = @MaKNQ 
  AND A.TYPE = 2                                  
  AND A._XORN = 'X' 
  AND A.MA_NGUON <> 'X4' 
  AND A.TRANG_THAI = 'T' 
  AND ((A.PB_PHIEU = 'CT' AND A.DPHIEUID_NEXT IS NULL) OR (A.PB_PHIEU = 'SU' AND A.DPHIEUID_PREV IS NOT NULL))
  AND A.NGAY_PHIEU >= @StartDate 
  AND A.NGAY_PHIEU <= @EndDate
GROUP BY A.TYPE, A.SOTK, A.NGAY_DK, A.SO_PHIEU, A.NGAY_PHIEU, A.DPHIEUID, A.DHOPDONGID, A.SO_HD, A.NGAY_HD, 
         B.SO_PHIEU_N, B.STTHANG_N, B.STTHANG, B.SO_TK, CAST(B.NGAY_DK AS DATE), B.MA_SP, B.DINH_DANH_HANG_HOA, B.SO_CONT;

-- --------------------------------------------------------------------
-- STEP 3: 引入海关监督【强制销毁（Tiêu hủy）】数据平账
-- --------------------------------------------------------------------
INSERT INTO #XUAT 
SELECT 
    CAST('' AS NVARCHAR(100)) AS CKEYS, 2 AS TYPE, '' AS SOTK_X, NULL AS NGAY_DK_X, B.SO_PHIEU, B.NGAY_PHIEU, 0 AS DPHIEUID, A.DHOPDONGID, A.SO_HD, H.NGAY_NHAP AS NGAY_HD, E.SO_BBBG, '' AS SO_CHUNG_TU, '' AS TEN_NGUOI_NHAN_HANG, A.SO_KIEN, E.PHUONG_TIEN, A.SO_PHIEU_N, E.STTHANG_N, NULL STTHANG, E.SO_TK, CAST(E.NGAY_DK AS DATE) AS NGAY_DK, A.MA_SP, A.DINH_DANH_HANG_HOA, E.SO_CONT, A.TEN_SP, E.MA_NUOC, E.MA_HS, A.SO_LUONG, A.MA_DVT, E.TRONG_LUONG_GW, E.TRONG_LUONG_NW, E.TRI_GIA, E.VI_TRI_HANG, I.TEN_DVT, T.TEN_CK, '' AS SO_SEAL, CAST(N'Hàng tiêu hủy' AS NVARCHAR(250)) AS GHI_CHU, A.GHI_CHU AS GHI_CHU_HANG, E.NGAY_PHIEU AS NGAY_NHAP, CAST(NULL AS INT) AS SO_NGAY_TON, '' AS SO_QUAN_LY
FROM DTIEUHUY_CT A WITH (NOLOCK)
INNER JOIN DTIEUHUY B WITH (NOLOCK) ON A.DTIEUHUYID = B.DTIEUHUYID
INNER JOIN (
    SELECT D.DHOPDONGID, D.SO_PHIEU, D.NGAY_PHIEU, D.SO_BBBG, D.PHUONG_TIEN, D.MA_CK_XUAT, D.MA_NGUON, C.STTHANG_N, C.DINH_DANH_HANG_HOA, C.SO_TK, CAST(C.NGAY_DK AS DATE) AS NGAY_DK, C.SO_CONT, C.MA_NUOC, C.MA_HS, C.TRONG_LUONG_NW, C.TRONG_LUONG_GW, C.TRI_GIA, C.VI_TRI_HANG
    FROM DPHIEU_HANG C 
    INNER JOIN DPHIEU D ON C.DPHIEUID = D.DPHIEUID AND D.MA_KNQ = @MaKNQ AND D.TYPE = 2 AND D._XORN = 'N' AND D.TRANG_THAI = 'T' AND ((D.PB_PHIEU = 'CT' AND D.DPHIEUID_NEXT IS NULL) OR (D.PB_PHIEU = 'SU' AND D.DPHIEUID_PREV IS NOT NULL))
) E ON A.DHOPDONGID = E.DHOPDONGID AND A.DINH_DANH_HANG_HOA = E.DINH_DANH_HANG_HOA AND A.SO_PHIEU_N = E.SO_PHIEU 
INNER JOIN DHOPDONG H WITH (NOLOCK) ON A.DHOPDONGID = H.DHOPDONGID 
LEFT JOIN SDVT I WITH (NOLOCK) ON A.MA_DVT = I.MA_DVT 
LEFT JOIN SCUAKHAU T WITH (NOLOCK) ON T.MA_CK = E.MA_CK_XUAT
WHERE B.MA_KNQ = @MaKNQ AND B.TRANG_THAI = '1' AND B.NGAY_PHIEU >= @StartDate AND B.NGAY_PHIEU <= @EndDate;

-- --------------------------------------------------------------------
-- STEP 4: 穿透溯源原始入库单 (彻底补全报关单、合同、原始入库日期与库龄)
-- --------------------------------------------------------------------
UPDATE X SET 
    X.SO_TK = ISNULL(NULLIF(X.SO_TK, ''), PN.SO_TK), 
    X.NGAY_DK = ISNULL(X.NGAY_DK, CAST(PN.NGAY_DK AS DATE)), 
    X.SO_HD = ISNULL(NULLIF(X.SO_HD, ''), P.SO_HD), 
    X.NGAY_HD = ISNULL(X.NGAY_HD, P.NGAY_HD), 
    X.NGAY_NHAP = ISNULL(X.NGAY_NHAP, CAST(P.NGAY_PHIEU AS DATE))
FROM #XUAT X
INNER JOIN DPHIEU P WITH (NOLOCK) ON X.SO_PHIEU_N = P.SO_PHIEU AND P.MA_KNQ = @MaKNQ AND P._XORN = 'N'
INNER JOIN DPHIEU_HANG PN WITH (NOLOCK) ON P.DPHIEUID = PN.DPHIEUID AND X.DINH_DANH_HANG_HOA = PN.DINH_DANH_HANG_HOA;

-- 库龄穿透校正 (因为 NGAY_NHAP 已经补全，现在 DATEDIFF 可以算出真实的库存天数了)
UPDATE #XUAT SET SO_NGAY_TON = DATEDIFF(dd, NGAY_NHAP, NGAY_PHIEU) + 1;

-- --------------------------------------------------------------------
-- STEP 5: 展现最纯正的出库明细流水账册 (完美对齐Excel表头与字段顺序)
-- --------------------------------------------------------------------
SELECT 
    ROW_NUMBER() OVER(ORDER BY NGAY_PHIEU DESC, SO_PHIEU DESC) AS [STT], -- [系统] 序号
    SO_TK AS [Số TK nhập],                  -- [入库报关] 历史进口报关单号
    NGAY_DK AS [Ngày TK],                   -- [入库报关] 历史进口报关单日期
    SO_HD AS [Số hợp đồng],                 -- [合规] 保税合同号
    NGAY_HD AS [Ngày hợp đồng],             -- [合规] 合同录入日期
    SO_PHIEU AS [Số phiếu],                 -- [出库单] 出库单号
    NGAY_PHIEU AS [Ngày phiếu],             -- [出库单] 出库日期
    SO_CHUNG_TU AS [Chứng từ nội bộ],       -- [物流] 内部随附凭证号
    TONG_SO_KIEN AS [Tổng số kiện],         -- [物控] 出库总件数
    TEN_NGUOI_NHAN_HANG AS [Người nhận hàng], -- [客户] 提货人/收货人名称
    SOTK_X AS [Số tờ khai/CT],              -- [出库报关] 出口报关单号/证明
    NGAY_DK_X AS [Ngày tờ khai],            -- [出库报关] 出口报关单注册日期
    NGAY_PHIEU AS [Ngày xuất kho],          -- [出库单] 实际出库日期 (映射为 Ngày phiếu)
    NGAY_NHAP AS [Ngày nhập],               -- [溯源] 该批货物的历史真实入库日期
    SO_NGAY_TON AS [Số ngày tồn],           -- [库龄] 出库时该批货物的实际在库天数
    MA_SP AS [Mã hàng],                     -- [商品] 商品编码
    TEN_SP AS [Tên hàng],                   -- [商品] 商品品名
    MA_NUOC AS [Xuất xứ],                   -- [商品] 原产国代码
    SO_LUONG AS [Lượng],                    -- [物控] 实际出库数量
    TEN_DVT AS [Đơn vị tính],               -- [字典] 计量单位名称
    TRONG_LUONG_GW AS [Trọng lượng GW],     -- [物控] 毛重-GW
    TRONG_LUONG_NW AS [Trọng lượng NW],     -- [物控] 净重-NW
    TRI_GIA AS [Trị Giá],                   -- [财务] 出库总货值
    SO_QUAN_LY AS [Số quản lý NB],          -- [报关] 海关管理编号
    SO_CONT AS [Số container],              -- [仓配] 集装箱柜号
    SO_SEAL AS [Số chì HQ],                 -- [仓配] 海关铅封号
    GHI_CHU AS [Ghi chú],                   -- [系统] 系统级动作备注 (如:销毁等)
    GHI_CHU_HANG AS [Ghi chú hàng]          -- [业务] 货物明细级备注
FROM #XUAT 
ORDER BY [Ngày phiếu] DESC, [Số phiếu] DESC;

-- 清理临时表缓存
DROP TABLE #XUAT;