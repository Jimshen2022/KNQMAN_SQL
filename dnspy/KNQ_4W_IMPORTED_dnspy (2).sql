-- ====================================================================
-- 完美克隆：ECUS5 保税仓货物入库明细流水账（KNQ_4W_IMPORTED）
-- （列名与系统原生字段 100% 一致，附带详尽中文业务注释）
-- ====================================================================
SET NOCOUNT ON;

DECLARE @MaKNQ NVARCHAR(50) = 'VNNSL';          --【变量：保税仓代码】
DECLARE @StartDate DATETIME = '2026-04-01';     --【变量：入库开始日期】
DECLARE @EndDate DATETIME = '2026-05-17';       --【变量：入库结束日期】

-- --------------------------------------------------------------------
-- STEP 1: 提取所有【集装箱重箱（Type = 1）】的正式生效入库流水
-- --------------------------------------------------------------------
IF OBJECT_ID('tempdb..#NHAP') IS NOT NULL DROP TABLE #NHAP;

SELECT 
    CAST(CAST(A.DHOPDONGID AS VARCHAR) + ';' + CAST(A.TYPE AS VARCHAR) + ';' + CAST(B.DINH_DANH_HANG_HOA AS VARCHAR) + ';' AS NVARCHAR(100)) AS CKEYS, 
    A.DHOPDONGID, A.TYPE, A.SO_PHIEU, A.NGAY_PHIEU, A.DPHIEUID, A.SO_HD, A.NGAY_HD, A.MA_NGUON, A.SO_BBBG, A.SO_CHUNG_TU, A.TEN_NGUOI_GIAO_HANG, A.TONG_SO_KIEN,
    B.DPHIEU_HANGID, B.SO_TK, CAST(B.NGAY_DK AS DATE) AS NGAY_DK, B.DINH_DANH_HANG_HOA, B.MA_SP, B.TEN_SP, B.STTHANG, B.MA_NUOC, B.SO_LUONG, B.MA_DVT, B.TRONG_LUONG_GW, B.TRONG_LUONG_NW, 
    B.DON_GIA AS GIA_NHAP, B.TRI_GIA, B.MA_HS, B.VI_TRI_HANG, B.SO_CONT, 
    D.SO_SEAL, S.TEN_NGUON, T.TEN_DVT, G.TEN_KH, 
    CAST('' AS NVARCHAR(100)) AS GHI_CHU, 
    B.GHI_CHU AS GHI_CHU_HANG, B.SO_QUAN_LY
INTO #NHAP 
FROM DPHIEU A WITH (NOLOCK)
INNER JOIN DPHIEU_HANG B WITH (NOLOCK) ON A.DPHIEUID = B.DPHIEUID AND ISNULL(B.IS_HUY, 0) = 0
INNER JOIN DCONTAINER D WITH (NOLOCK) ON D.DPHIEUID = A.DPHIEUID AND D.SO_CONT = B.SO_CONT AND ISNULL(D.IS_HUY, 0) = 0
LEFT JOIN DHOPDONG F WITH (NOLOCK) ON A.DHOPDONGID = F.DHOPDONGID 
LEFT JOIN SKHACHHANG G WITH (NOLOCK) ON G.MA_KH = F.MA_KH AND F.MA_KNQ = G.MA_KNQ
LEFT JOIN SNGUONHANG S WITH (NOLOCK) ON S.MA_NGUON = A.MA_NGUON 
LEFT JOIN SDVT T WITH (NOLOCK) ON B.MA_DVT = T.MA_DVT
WHERE A.MA_KNQ = @MaKNQ 
  AND A.TYPE = 1 
  AND A._XORN = 'N' 
  AND A.TRANG_THAI = 'T' 
  AND ((A.PB_PHIEU = 'CT' AND A.DPHIEUID_NEXT IS NULL) OR (A.PB_PHIEU = 'SU' AND A.DPHIEUID_PREV IS NOT NULL))
  AND A.NGAY_PHIEU >= @StartDate 
  AND A.NGAY_PHIEU <= @EndDate;

-- --------------------------------------------------------------------
-- STEP 2: 【去重排除】扣减剔除掉在库内已经办理了“掏箱落地”的重箱流水
-- --------------------------------------------------------------------
IF OBJECT_ID('tempdb..#DRUTHANG') IS NOT NULL DROP TABLE #DRUTHANG;

SELECT A.DPHIEUID, A.SO_CONT, B.SO_DINH_DANH AS DINH_DANH_HANG_HOA 
INTO #DRUTHANG 
FROM DRUTHANG A WITH (NOLOCK)
INNER JOIN DRUTHANG_CT B WITH (NOLOCK) ON A.DRUTHANGID = B.DRUTHANGID
WHERE A.MA_KNQ = @MaKNQ AND A.TRANG_THAI = 2 
GROUP BY A.DPHIEUID, A.SO_CONT, B.SO_DINH_DANH;

DELETE #NHAP FROM #NHAP A, #DRUTHANG B WHERE A.DPHIEUID = B.DPHIEUID AND A.SO_CONT = B.SO_CONT;
DROP TABLE #DRUTHANG;

-- --------------------------------------------------------------------
-- STEP 3: 追加写入所有【普通散货 / 件货（Type = 2）】的正式生效入库明细
-- --------------------------------------------------------------------
INSERT INTO #NHAP 
SELECT 
    CAST(CAST(A.DHOPDONGID AS VARCHAR) + ';' + CAST(A.TYPE AS VARCHAR) + ';' + CAST(B.DINH_DANH_HANG_HOA AS VARCHAR) + ';' AS NVARCHAR(100)) AS CKEYS, 
    A.DHOPDONGID, A.TYPE, A.SO_PHIEU, A.NGAY_PHIEU, A.DPHIEUID, A.SO_HD, A.NGAY_HD, A.MA_NGUON, A.SO_BBBG, A.SO_CHUNG_TU, A.TEN_NGUOI_GIAO_HANG, A.TONG_SO_KIEN,
    B.DPHIEU_HANGID, B.SO_TK, CAST(B.NGAY_DK AS DATE) AS NGAY_DK, B.DINH_DANH_HANG_HOA, B.MA_SP, B.TEN_SP, B.STTHANG, B.MA_NUOC, B.SO_LUONG, B.MA_DVT, B.TRONG_LUONG_GW, B.TRONG_LUONG_NW, 
    B.DON_GIA, B.TRI_GIA AS GIA_NHAP, B.MA_HS, B.VI_TRI_HANG, B.SO_CONT, 
    '' AS SO_SEAL, S.TEN_NGUON, T.TEN_DVT, G.TEN_KH, 
    CAST('' AS NVARCHAR(100)) AS GHI_CHU, 
    B.GHI_CHU AS GHI_CHU_HANG, B.SO_QUAN_LY
FROM DPHIEU A WITH (NOLOCK)
INNER JOIN DPHIEU_HANG B WITH (NOLOCK) ON A.DPHIEUID = B.DPHIEUID AND ISNULL(B.IS_HUY, 0) = 0
LEFT JOIN DHOPDONG F WITH (NOLOCK) ON A.DHOPDONGID = F.DHOPDONGID 
LEFT JOIN SKHACHHANG G WITH (NOLOCK) ON G.MA_KH = F.MA_KH AND F.MA_KNQ = G.MA_KNQ
LEFT JOIN SNGUONHANG S WITH (NOLOCK) ON S.MA_NGUON = A.MA_NGUON 
LEFT JOIN SDVT T WITH (NOLOCK) ON B.MA_DVT = T.MA_DVT
WHERE A.MA_KNQ = @MaKNQ 
  AND A.TYPE = 2 
  AND A._XORN = 'N' 
  AND A.TRANG_THAI = 'T' 
  AND ((A.PB_PHIEU = 'CT' AND A.DPHIEUID_NEXT IS NULL) OR (A.PB_PHIEU = 'SU' AND A.DPHIEUID_PREV IS NOT NULL))
  AND A.NGAY_PHIEU >= @StartDate 
  AND A.NGAY_PHIEU <= @EndDate;

-- --------------------------------------------------------------------
-- STEP 4: 联动计算“仓内所有权虚拟过户（Chuyển quyền）”的数量分摊冲抵
-- --------------------------------------------------------------------
IF OBJECT_ID('tempdb..#DVANBAN') IS NOT NULL DROP TABLE #DVANBAN;

SELECT 
    CAST(CAST(DHOPDONGID_GUI AS VARCHAR) + ';' + CAST(TYPE AS VARCHAR) + ';' + CAST(DINH_DANH_HANG_HOA AS VARCHAR) + ';' AS NVARCHAR(100)) AS CKEYS, 
    B.DVANBANID, B.DHOPDONGID_GUI, F.SO_HD AS SO_HD_GUI, B.DHOPDONGID_NHAN, G.SO_HD AS SO_HD_NHAN, 
    B.SOTK, A.TYPE, A.SO_PHIEU_N, A.STTHANG_N, A.MA_SP, A.DINH_DANH_HANG_HOA, A.SO_LUONG, A.TRI_GIA 
INTO #DVANBAN 
FROM DVANBAN_HANG A WITH (NOLOCK), DVANBAN B WITH (NOLOCK), DHOPDONG F WITH (NOLOCK), DHOPDONG G WITH (NOLOCK)
WHERE B.MA_KNQ = @MaKNQ AND B.TRANG_THAI = '2' AND A.DVANBANID = B.DVANBANID 
  AND B.DHOPDONGID_GUI = F.DHOPDONGID AND B.DHOPDONGID_NHAN = G.DHOPDONGID
  AND (EXISTS(SELECT 1 FROM #NHAP C WHERE B.DHOPDONGID_GUI = C.DHOPDONGID GROUP BY C.DHOPDONGID) 
       OR EXISTS(SELECT 1 FROM #NHAP C WHERE B.DHOPDONGID_NHAN = C.DHOPDONGID GROUP BY C.DHOPDONGID));

-- 更新转入货物的账面高可读备注
UPDATE #NHAP 
SET GHI_CHU = TEN_NGUON + N' từ HD số: ' + SO_HD_GUI 
FROM #NHAP A, #DVANBAN B 
WHERE A.MA_NGUON = 'N4' 
  AND A.TYPE = B.TYPE AND A.DHOPDONGID = B.DHOPDONGID_NHAN 
  AND A.DINH_DANH_HANG_HOA = B.DINH_DANH_HANG_HOA AND A.MA_SP = B.MA_SP AND A.SO_LUONG = B.SO_LUONG;

IF OBJECT_ID('tempdb..#NHAP2') IS NOT NULL DROP TABLE #NHAP2;
IF OBJECT_ID('tempdb..#DVANBAN2') IS NOT NULL DROP TABLE #DVANBAN2;

SELECT ROW_NUMBER() OVER(PARTITION BY CKEYS ORDER BY NGAY_PHIEU, DPHIEUID, DPHIEU_HANGID) AS STT, *, SO_LUONG AS SO_LUONG2, TRI_GIA AS TRI_GIA2, 0*SO_LUONG AS SO_LUONG_SD, TRI_GIA AS TRI_GIA_SD 
INTO #NHAP2 FROM #NHAP;

SELECT CKEYS, SUM(SO_LUONG) AS SO_LUONG, 0*SUM(SO_LUONG) AS SO_LUONG_SD, SUM(SO_LUONG) AS SO_LUONG_TON, SUM(TRI_GIA) TRI_GIA, 0*SUM(TRI_GIA) AS TRI_GIA_SD, SUM(TRI_GIA) AS TRI_GIA_TON 
INTO #DVANBAN2 FROM #DVANBAN A GROUP BY CKEYS;

DROP TABLE #NHAP, #DVANBAN;

-- 循环消减过户部分的额度
DECLARE @i INT = 1, @j INT = ISNULL((SELECT MAX(STT) FROM #NHAP2), 1);
WHILE (@i <= @j)
BEGIN
    UPDATE #NHAP2 SET SO_LUONG_SD = CASE WHEN B.SO_LUONG_TON > A.SO_LUONG THEN A.SO_LUONG ELSE B.SO_LUONG_TON END, TRI_GIA_SD = CASE WHEN B.TRI_GIA_TON > A.TRI_GIA THEN A.TRI_GIA ELSE B.TRI_GIA_TON END FROM #NHAP2 A, #DVANBAN2 B WHERE A.CKEYS = B.CKEYS AND B.SO_LUONG_TON > 0 AND STT = @i;
    UPDATE #DVANBAN2 SET SO_LUONG_SD = B.SO_LUONG_SD, TRI_GIA_SD = B.TRI_GIA_SD FROM #DVANBAN2 A, (SELECT CKEYS, SUM(SO_LUONG_SD) SO_LUONG_SD, SUM(TRI_GIA_SD) TRI_GIA_SD FROM #NHAP2 WHERE SO_LUONG_SD > 0 GROUP BY CKEYS) B WHERE A.CKEYS = B.CKEYS;
    UPDATE #DVANBAN2 SET SO_LUONG_TON = SO_LUONG - SO_LUONG_SD, TRI_GIA_TON = TRI_GIA - TRI_GIA_SD;
    SET @i += 1;
END;

-- 计算净输入留存资产，并对已经全单过户转走的死笔执行斩杀（DELETE）
UPDATE #NHAP2 SET SO_LUONG = SO_LUONG2 - SO_LUONG_SD, TRI_GIA = TRI_GIA2 - SO_LUONG_SD * GIA_NHAP;
UPDATE #NHAP2 SET GHI_CHU = N'Xuất chuyển quyền sang hợp đồng khác : ' + CAST(SO_LUONG_SD AS VARCHAR) WHERE SO_LUONG_SD > 0;
DELETE #NHAP2 WHERE SO_LUONG = 0;

DROP TABLE #DVANBAN2;

-- --------------------------------------------------------------------
-- STEP 5: 展现最纯正的入库明细流水账册 (对齐原始表头列名并附带中文注释)
-- --------------------------------------------------------------------
SELECT 
    SO_PHIEU,             -- [基础] 初始入库单号 (Số phiếu)
    NGAY_PHIEU,           -- [基础] 初始入仓日期 (Ngày phiếu)
    SO_HD,                -- [合规] 保税合同号 (Số hợp đồng)
    NGAY_HD,              -- [合规] 保税合同录入日期 (Ngày hợp đồng)
    MA_NGUON,             -- [来源] 货物来源属性代码 (Mã nguồn)
    SO_TK,                -- [报关] 海关进口报关单号 (Số tờ khai)
    NGAY_DK,              -- [报关] 报关单申报注册日期 (Ngày đăng ký)
    DINH_DANH_HANG_HOA,   -- [溯源] 货物海关唯一定标码 (Định danh hàng hóa)
    MA_SP,                -- [商品] 内部商品编码 (Mã sản phẩm)
    TEN_SP,               -- [商品] 商品综合品名 (Tên sản phẩm)
    MA_NUOC,              -- [商品] 原产国代码 (Mã nước)
    SO_LUONG,             -- [物控] 实际入库净数量 (Số lượng)
    MA_DVT,               -- [物控] 计量单位编码 (Mã ĐVT)
    TRONG_LUONG_GW,       -- [物控] 毛重-Gross Weight (Trọng lượng GW)
    TRONG_LUONG_NW,       -- [物控] 净重-Net Weight (Trọng lượng NW)
    GIA_NHAP,             -- [财务] 原始进口单价 (Đơn giá nhập)
    TRI_GIA,              -- [财务] 进口总货值 (Trị giá)
    MA_HS,                -- [报关] 海关HS税号 (Mã HS)
    VI_TRI_HANG,          -- [仓配] 仓库物理货位格 (Vị trí hàng)
    SO_CONT,              -- [仓配] 集装箱柜号 (Số Container)
    SO_SEAL,              -- [仓配] 海关铅封号 (Số Seal)
    TEN_NGUON,            -- [字典] 货物来源类型说明 (Tên nguồn)
    TEN_DVT,              -- [字典] 计量单位名称说明 (Tên ĐVT)
    TEN_KH,               -- [客户] 货主客户名称 (Tên khách hàng)
    GHI_CHU               -- [其他] 虚拟过户及补充备注 (Ghi chú)
FROM #NHAP2 
ORDER BY NGAY_PHIEU DESC, SO_PHIEU DESC, STTHANG ASC;

-- 清理临时表缓存
DROP TABLE #NHAP2;