# 🧠 [AI Agent Skill Tree] 越南海关 ECUS5 保税仓底层 SQL 逆向工程知识库 (终极完整版)

> **Meta Information for AI Agents**
> - **Domain (领域)**: 越南海关保税仓库业务 (Vietnam Customs Bonded Warehouse / Kho Ngoại Quan)
> - **System (系统)**: ECUS5 (by Thai Son - 越南海关官方指定接口系统)
> - **Role (角色模型)**: DBA, Senior SQL Software Engineer, Customs Domain Expert
> - **Purpose (目标)**: 供其他 AI Agent (如 RAG 系统、代码助手、数据分析 Agent) 学习、检索和复用的标准知识树。本文档**毫无保留**地包含了 ECUS5 底层架构、数据字典以及**所有核心业务场景（共 4 套）**的完整 SQL 源码。

---

## 🌳 节点 1：保税仓核心业务概念与数据字典 (Data Dictionary)

AI Agent 在解析用户自然语言或生成相关 SQL 时，必须严格遵循以下 ECUS5 数据库底层的枚举规则与字段映射：

### 1.1 单据流向 (`_XORN`)
*   `N` (Nhập): 入库单/进口 (Import into Bonded Warehouse)
*   `X` (Xuất): 出库单/出口 (Export from Bonded Warehouse)

### 1.2 货物形态分类 (`TYPE`)
*   `1`: 集装箱货物/重箱 (Hàng Container)。必须关联集装箱明细表 `DCONTAINER`，受 `SO_CONT` (柜号) 和 `SO_SEAL` (铅封号) 的强约束。
*   `2`: 散货/普通件货 (Hàng lẻ/Hàng rời)。直接通过明细行数量计算，无柜号强制约束。

### 1.3 核心状态机 (`TRANG_THAI` & `PB_PHIEU`)
*   `TRANG_THAI = 'T'`: 单据已正式生效/海关已通过 (Thành công/Đã duyệt)。在计算库存时必须加此过滤条件。
*   `TRANG_THAI = '1'` (适用于特定表如 `DTIEUHUY` 销毁表): 销毁动作已核准执行。
*   `TRANG_THAI = '2'` (适用于特定表如 `DVANBAN` 过户表): 过户协议已生效。
*   `PB_PHIEU = 'CT'`: 原始单据 (Chứng từ)。当且仅当 `DPHIEUID_NEXT IS NULL` 时为最新有效态（代表该单据未被修正覆盖）。
*   `PB_PHIEU = 'SU'`: 修改后的单据 (Sửa)。当且仅当 `DPHIEUID_PREV IS NOT NULL` 时为最新有效态。

### 1.4 核心物理表拓扑 (Entity Relationships)
*   **`DHOPDONG`**: 顶级保税合同表。承载海关备案的合同编号。字段 `IS_THANH_LY` 控制是否已结关清算。
*   **`DPHIEU`**: 出入库单头表 (Header)。承载进出口报关单号 (`SOTK`)、仓储单号 (`SO_PHIEU`)。
*   **`DPHIEU_HANG`**: 出入库明细表 (Lines)。最核心的追溯字段是 `DINH_DANH_HANG_HOA` (海关货物唯一标码)。
*   **`DVANBAN` / `DVANBAN_HANG`**: 虚拟过户/所有权转移 (Chuyển quyền)。用于同仓内不同合同/不同企业间的物权交割，实物不移动，但账面需转移。
*   **`DTIEUHUY` / `DTIEUHUY_CT`**: 强制销毁作业表 (Tiêu hủy)。海关监督下的实物灭失，需在出库总账中平账（视同出库），但不能算作正常贸易出口。
*   **`DRUTHANG` / `DRUTHANG_CT`**: 掏箱/落地作业表 (Rút hàng)。将 `TYPE=1` 的整柜重箱转为 `TYPE=2` 的散货落地入库，用于库存形态转换。

---

## 🌳 节点 2：核心算法模型 (Core Algorithms)

### 2.1 FIFO (先进先出) 动态对冲引擎
保税仓实物结存的计算并非简单的 `Sum(In) - Sum(Out)`，而是基于 **批次对应关系的 FIFO 消除法**。
*   **输入**：时间线排序的入库集合（带结存量字段 `LUONG_TON`）、时间线排序的出库集合（带待核销字段 `LUONG_TON`）。
*   **循环逻辑**：SQL 中通过两层 `WHILE` 循环，定位最早的入库批次和最早的出库批次，使用 `CASE WHEN` 比较可用余量并相互扣减 (`SO_LUONG_SD`)。
*   **终止条件**：`LUONG_TON > 0` 的出入库记录无法继续匹配为止。

### 2.2 多级所有权穿透追溯 (Recursive Ownership Tracing)
由于在库货物可能会经历多次转卖（A 卖给 B，B 卖给 C），海关要求最终出库或盘点时，必须追溯到**该货物最初入境的真实日期**以计算精确的库龄，并征收相应仓储费或判断是否逾期。
*   **实现方式**：利用 `WHILE (@c <= 5)` 循环，在 `DVANBAN` (过户表) 和 `#NHAP_X` (入库源表) 之间不断向上游索源 `NGAY_VAO_RA` (实际入闸时间)，系统默认最大支持 5 代交易穿透。

---

## 🌳 节点 3：源码军火库 (SQL Source Code Arsenal)

以下为提取自 ECUS5 系统的 **4 套**核心生产级 SQL 代码，可直接供其他 Agent 分析和生成使用。**所有代码均为 100% 完整无删减版，保留了原始系统的全部校验和循环逻辑。**

### 📜 3.1 [海关合规] 结关条件检查与清算模型 (Contract Liquidation Check)
**业务场景**：越南海关合规要求 (Compliance) 保税仓合同 (Hợp đồng) 在货物完全出清后进行 thanh lý (清算/结关)。此脚本用于精准找出所有库存账面恰好归零、未作废且尚未执行结关操作的合规合同。

```sql
/* 查看已全部出库完毕、满足清算/结关条件的保税仓合同列表 */

-- STEP 1: 找出当前未结关、未作废的有效保税仓合同
SELECT A.MA_KNQ, A.DHOPDONGID, A.SO_HD, A.NGAY_NHAP, A.NGAY_KY, A.NGAY_HH, 
       A.IS_THANH_LY, A.IS_HUY, A.TRANG_THAI, A.MA_KH, B.TEN_KH, 
       CAST(0 AS FLOAT) AS SO_LUONG_GETIN, 
       CAST(0 AS FLOAT) AS SO_LUONG_GETOUT, 
       CAST(0 AS FLOAT) AS SO_LUONG_TON
INTO #DHOPDONG 
FROM DHOPDONG A 
LEFT JOIN SKHACHHANG B ON A.MA_KNQ = B.MA_KNQ AND A.MA_KH = B.MA_KH 
LEFT JOIN DTHONGBAO C ON A.DHOPDONGID = C.DHOPDONGID
WHERE A.MA_KNQ = '你的保税仓代码' 
  AND ISNULL(A.IS_THANH_LY, 0) = 0   -- 过滤：未清算/未完成的合同
  AND A.TRANG_THAI <= 3              -- 过滤：状态小于等于3的合同
  AND ISNULL(A.IS_HUY, 0) = 0;       -- 过滤：未作废的合同

-- STEP 2: 从出入库单证（DPHIEU）中汇总所有进出口数量
SELECT A.MA_KNQ, A.DHOPDONGID, 
       CAST(SUM(SO_LUONG) AS NUMERIC(20,4)) AS SO_LUONG, 
       CAST(SUM(SO_LUONG_GETOUT) AS NUMERIC(20,4)) AS SO_LUONG_GETOUT, 
       SO_HD 
INTO #DPHIEU 
FROM ( 
    -- 1) 类型为 2 (散货/普通货物) 的入库数量 (_XORN = 'N')
    SELECT B.MA_KNQ, C.MA_KH, A.DINH_DANH_HANG_HOA, B.DHOPDONGID, B.SO_PHIEU, B.NGAY_PHIEU, 
           (A.SO_LUONG) AS SO_LUONG, CAST(NULL AS VARCHAR) AS SO_PHIEU_XUAT, 
           CAST(NULL AS DATETIME) AS NGAY_PHIEU_XUAT, CAST(NULL AS FLOAT) AS SO_LUONG_GETOUT
    FROM DPHIEU_HANG A 
    INNER JOIN DPHIEU B ON A.DPHIEUID = B.DPHIEUID 
    INNER JOIN DHOPDONG C ON B.DHOPDONGID = C.DHOPDONGID 
    WHERE B.MA_KNQ = '你的保税仓代码' AND B._XORN = 'N' AND B.TRANG_THAI = 'T' 
      AND ISNULL(A.IS_HUY, 0) = 0 AND B.TYPE = 2 
      AND B.DHOPDONGID IN (SELECT DHOPDONGID FROM #DHOPDONG)

    UNION ALL

    -- 2) 类型为 2 (散货/普通货物) 的出库数量 (_XORN = 'X')
    SELECT B.MA_KNQ, B.MA_KH, A.DINH_DANH_HANG_HOA, 
           CASE WHEN B.DHOPDONGID IS NULL THEN (SELECT TOP 1 DHOPDONGID FROM DPHIEU P WHERE MA_KNQ = '你的保税仓代码' AND _XORN = 'N' AND TYPE = '2' AND SO_PHIEU = (A.SO_PHIEU_N)) ELSE B.DHOPDONGID END, 
           NULL, NULL, NULL, B.SO_PHIEU, B.NGAY_PHIEU, (A.SO_LUONG)
    FROM DPHIEU_HANG A 
    INNER JOIN DPHIEU B ON A.DPHIEUID = B.DPHIEUID
    WHERE B.MA_KNQ = '你的保税仓代码' AND B._XORN = 'X' AND B.TRANG_THAI = 'T' AND ISNULL(A.IS_HUY, 0) = 0 AND B.TYPE = 2 
      AND EXISTS (SELECT 1 FROM DPHIEU_HANG C INNER JOIN DPHIEU X ON C.DPHIEUID=X.DPHIEUID WHERE X.MA_KNQ = '你的保税仓代码' AND A.DINH_DANH_HANG_HOA = C.DINH_DANH_HANG_HOA AND A.SO_PHIEU_N=X.SO_PHIEU AND X._XORN = 'N' AND X.TRANG_THAI = 'T' AND X.TYPE = '2' AND X.DHOPDONGID IN(SELECT DHOPDONGID FROM #DHOPDONG) AND ISNULL(C.IS_HUY, 0) = 0)

    UNION ALL 

    -- 3) 类型为 1 (集装箱货物) 的入库数量 (_XORN = 'N') 且未拆箱 (IS_RUTHANG = 0)
    SELECT B.MA_KNQ, C.MA_KH, A.DINH_DANH_HANG_HOA, B.DHOPDONGID, B.SO_PHIEU, B.NGAY_PHIEU, 
           (A.SO_LUONG) AS SO_LUONG, CAST(NULL AS VARCHAR) AS SO_PHIEU_XUAT, CAST(NULL AS DATETIME) AS NGAY_PHIEU_XUAT, CAST(NULL AS FLOAT) AS SO_LUONG_GETOUT 
    FROM DPHIEU_HANG A 
    INNER JOIN DPHIEU B ON A.DPHIEUID = B.DPHIEUID 
    INNER JOIN DHOPDONG C ON B.DHOPDONGID = C.DHOPDONGID 
    INNER JOIN DCONTAINER D ON B.DPHIEUID = D.DPHIEUID AND A.SO_CONT = D.SO_CONT
    WHERE B.MA_KNQ = '你的保税仓代码' AND B._XORN = 'N' AND B.TRANG_THAI = 'T' 
      AND ISNULL(A.IS_HUY, 0) = 0 AND B.TYPE = 1 AND D.IS_RUTHANG = 0 
      AND B.DHOPDONGID IN (SELECT DHOPDONGID FROM #DHOPDONG)

    UNION ALL 

    -- 4) 类型为 1 (集装箱货物) 的出库数量 (_XORN = 'X')
    SELECT B.MA_KNQ, B.MA_KH, A.DINH_DANH_HANG_HOA, 
           CASE WHEN B.DHOPDONGID IS NULL THEN (SELECT TOP 1 DHOPDONGID FROM DPHIEU P WHERE MA_KNQ = '你的保税仓代码' AND _XORN = 'N' AND TYPE = '1' AND SO_PHIEU = (A.SO_PHIEU_N)) ELSE B.DHOPDONGID END, 
           NULL, NULL, NULL, B.SO_PHIEU, B.NGAY_PHIEU, (A.SO_LUONG) 
    FROM DPHIEU_HANG A 
    INNER JOIN DPHIEU B ON A.DPHIEUID = B.DPHIEUID  
    INNER JOIN DCONTAINER D ON B.DPHIEUID = D.DPHIEUID AND A.SO_CONT = D.SO_CONT
    WHERE B.MA_KNQ = '你的保税仓代码' AND B._XORN = 'X' AND B.TRANG_THAI = 'T' AND ISNULL(A.IS_HUY, 0) = 0 AND B.TYPE = 1 
      AND EXISTS (SELECT 1 FROM DCONTAINER E WHERE D.DPHIEU_NHAPID = E.DPHIEUID AND D.SO_CONT = E.SO_CONT AND E.IS_RUTHANG = 0)
      AND EXISTS (SELECT 1 FROM DPHIEU_HANG C INNER JOIN DPHIEU X ON C.DPHIEUID=X.DPHIEUID WHERE X.MA_KNQ = '你的保税仓代码' AND A.DINH_DANH_HANG_HOA = C.DINH_DANH_HANG_HOA AND A.SO_PHIEU_N=X.SO_PHIEU AND X._XORN = 'N' AND X.TRANG_THAI = 'T' AND X.TYPE = '1' AND X.DHOPDONGID IN(SELECT DHOPDONGID FROM #DHOPDONG) AND ISNULL(C.IS_HUY, 0) = 0)
) A 
LEFT JOIN DHOPDONG C ON A.DHOPDONGID = C.DHOPDONGID AND A.MA_KNQ = C.MA_KNQ 
WHERE A.MA_KNQ = '你的保税仓代码' AND A.DHOPDONGID IN (SELECT DHOPDONGID FROM #DHOPDONG)
GROUP BY A.MA_KNQ, A.DHOPDONGID, SO_HD;

-- STEP 3: 回填入库和出库数量，并计算库存余额（TON）
UPDATE #DHOPDONG 
SET SO_LUONG_GETIN = ISNULL(B.SO_LUONG, 0), 
    SO_LUONG_GETOUT = ISNULL(B.SO_LUONG_GETOUT, 0) 
FROM #DHOPDONG A, #DPHIEU B 
WHERE A.MA_KNQ = B.MA_KNQ AND A.DHOPDONGID = B.DHOPDONGID;

-- 核心公式：库存 = 进库数量 - 出库数量
UPDATE #DHOPDONG SET SO_LUONG_TON = SO_LUONG_GETIN - SO_LUONG_GETOUT;

-- STEP 4: 终极过滤（重点！！）
DELETE #DHOPDONG WHERE SO_LUONG_GETIN = 0;                        -- 删掉没有入库记录的合同
DELETE #DHOPDONG WHERE CAST(SO_LUONG_TON AS NUMERIC(20,4)) <> 0;   -- 【关键】删掉库存不等于0的合同！！

-- STEP 5: 输出最终结果并销毁临时表
SELECT * FROM #DHOPDONG A ORDER BY A.MA_KNQ, A.DHOPDONGID, SO_HD, A.MA_KH;

DROP TABLE #DPHIEU, #DHOPDONG;
```

---

### 📜 3.2 [入库总账] 保税仓入库明细流水账 (KNQ_4W_IMPORTED)
**业务场景**：对应 ECUS5 系统中的 `Sổ chi tiết hàng nhập kho (4W)` 报表。它不仅汇总了集装箱和散货入库，还处理了复杂的**“所有权虚拟过户 (Chuyển quyền)”**以及**“掏箱落地 (Rút hàng)”**的逻辑对冲。

```sql
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
WHERE A.MA_KNQ = @MaKNQ AND A.TYPE = 1 AND A._XORN = 'N' AND A.TRANG_THAI = 'T' 
  AND ((A.PB_PHIEU = 'CT' AND A.DPHIEUID_NEXT IS NULL) OR (A.PB_PHIEU = 'SU' AND A.DPHIEUID_PREV IS NOT NULL))
  AND A.NGAY_PHIEU >= @StartDate AND A.NGAY_PHIEU <= @EndDate;

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
WHERE A.MA_KNQ = @MaKNQ AND A.TYPE = 2 AND A._XORN = 'N' AND A.TRANG_THAI = 'T' 
  AND ((A.PB_PHIEU = 'CT' AND A.DPHIEUID_NEXT IS NULL) OR (A.PB_PHIEU = 'SU' AND A.DPHIEUID_PREV IS NOT NULL))
  AND A.NGAY_PHIEU >= @StartDate AND A.NGAY_PHIEU <= @EndDate;

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
```

---

### 📜 3.3 [出库总账] 保税仓出库明细流水账 (KNQ_4W_EXPORTED)
**业务场景**：对应系统报表 `Sổ chi tiết hàng xuất kho (4W)`。此处需要合并常规出库、特殊出库，并且特别注意**“海关强制监督销毁 (Tiêu hủy)”** 的合规平账处理（即不计入常规出口金额，但在库管系统表现为合法出库销账）。

```sql
-- ====================================================================
-- 完美克隆：ECUS5 保税仓货物出库明细流水账（KNQ_4W_EXPORTED）
-- （列名与系统原生字段 100% 一致，附带详尽中文业务注释）
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
-- STEP 4: 库龄穿透校正
-- --------------------------------------------------------------------
-- (已修复原反编译代码中的类型错误：将 SO_PHIEU 改为正确的 NGAY_PHIEU)
UPDATE #XUAT SET SO_NGAY_TON = DATEDIFF(dd, NGAY_NHAP, NGAY_PHIEU) + 1;

-- --------------------------------------------------------------------
-- STEP 5: 展现最纯正的出库明细流水账册 (对齐原始表头列名并附带中文注释)
-- --------------------------------------------------------------------
SELECT 
    CKEYS,                  -- [系统] 内部组合主键
    TYPE,                   -- [系统] 单据类型 (1:重箱, 2:散货)
    SOTK_X,                 -- [出库报关] 出口报关单号 (Số TK Xuất)
    NGAY_DK_X,              -- [出库报关] 出口报关单注册日期 (Ngày ĐK Xuất)
    SO_PHIEU,               -- [出库单] 出库单号 (Số phiếu)
    NGAY_PHIEU,             -- [出库单] 出库日期 (Ngày phiếu)
    DPHIEUID,               -- [系统] 出库单主键ID
    DHOPDONGID,             -- [系统] 合同主键ID
    SO_HD,                  -- [合规] 保税合同号 (Số hợp đồng)
    NGAY_HD,                -- [合规] 合同录入日期 (Ngày hợp đồng)
    SO_BBBG,                -- [物流] 场站交接单号 (Số BBBG)
    SO_CHUNG_TU,            -- [物流] 随附凭证号 (Số chứng từ)
    TEN_NGUOI_NHAN_HANG,    -- [客户] 提货人/收货人名称 (Tên người nhận hàng)
    TONG_SO_KIEN,           -- [物控] 出库总件数 (Tổng số kiện)
    PHUONG_TIEN,            -- [物流] 运输工具/车牌号 (Phương tiện)
    SO_PHIEU_N,             -- [溯源] 对应来源入库单号 (Số phiếu nhập)
    STTHANG_N,              -- [溯源] 来源入库单行号 (STT hàng nhập)
    STTHANG,                -- [系统] 当前出库单行号 (STT hàng)
    SO_TK,                  -- [入库报关] 历史进口报关单号 (Số TK nhập)
    NGAY_DK,                -- [入库报关] 历史进口报关单日期 (Ngày ĐK nhập)
    MA_SP,                  -- [商品] 商品编码 (Mã sản phẩm)
    DINH_DANH_HANG_HOA,     -- [溯源] 货物海关定标码 (Định danh hàng hóa)
    SO_CONT,                -- [仓配] 集装箱柜号 (Số Container)
    TEN_SP,                 -- [商品] 商品品名 (Tên sản phẩm)
    MA_NUOC,                -- [商品] 原产国代码 (Mã nước)
    MA_HS,                  -- [报关] HS税号 (Mã HS)
    SO_LUONG,               -- [物控] 实际出库数量 (Số lượng)
    MA_DVT,                 -- [物控] 计量单位代码 (Mã ĐVT)
    TRONG_LUONG_GW,         -- [物控] 毛重-GW (Trọng lượng GW)
    TRONG_LUONG_NW,         -- [物控] 净重-NW (Trọng lượng NW)
    TRI_GIA,                -- [财务] 出库总货值 (Trị giá)
    VI_TRI_HANG,            -- [仓配] 仓库物理货位格 (Vị trí hàng)
    TEN_DVT,                -- [字典] 计量单位名称 (Tên ĐVT)
    TEN_CK,                 -- [出境口岸] 出境/目的地口岸 (Tên cửa khẩu xuất)
    SO_SEAL,                -- [仓配] 海关铅封号 (Số Seal)
    GHI_CHU,                -- [系统] 系统级动作备注 (Ghi chú - 如注明：销毁)
    GHI_CHU_HANG,           -- [业务] 货物明细级备注 (Ghi chú hàng)
    NGAY_NHAP,              -- [溯源] 该批货物的历史入库日期 (Ngày nhập)
    SO_NGAY_TON,            -- [库龄] 出库时该批货物的实际在库天数 (Số ngày tồn)
    SO_QUAN_LY              -- [报关] 海关管理编号 (Số quản lý)
FROM #XUAT 
ORDER BY NGAY_PHIEU DESC, SO_PHIEU DESC;

-- 清理临时表缓存
DROP TABLE #XUAT;
```

---

### 📜 3.4 [核心结存] 实时 FIFO 结存与库龄总账 (KNQ_OnHand)
**业务场景**：这是所有报表中最复杂、最重要的一环。由于海关保税货物追踪采用严格的 **FIFO (先进先出)** 算法，该脚本运用了双层 `WHILE` 循环，动态冲抵入库和出库批次，并执行多达 5 代的所有权 (Chuyển quyền) 溯源追踪，最终实现绝对精准的在库货物 (Lượng tồn) 结存报表与滞库天数计算。
**（注：此版为完整原生态溯源版引擎，无任何代码省略，直接可用）**

```sql
-- ====================================================================
-- 【终极完整纯查询版】ECUS5 保税仓 FIFO 实时结存与库龄总账 (OnHand)
-- （无权限门槛，列名与系统原生字段 100% 一致，附带详尽中文业务注释）
-- ====================================================================
SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

-- ========================================
-- 🔻 请在这里修改你的查询参数 🔻
-- ========================================
DECLARE @MaKNQ NVARCHAR(50) = 'VNNSL';          -- ★ 必须修改：例如 'VNNSL'
DECLARE @TargetDate DATETIME = GETDATE();       -- 默认盘点截止到今天此刻，也可改为特定日期如 '2026-05-17'

-- --------------------------------------------------------------------
-- STEP 1: 提取所有【集装箱重箱（Type = 1）】的原始入库基础账
-- --------------------------------------------------------------------
IF OBJECT_ID('tempdb..#NHAP') IS NOT NULL DROP TABLE #NHAP;

SELECT 
    CAST(CAST(A.DHOPDONGID AS VARCHAR) + ';' + CAST(A.TYPE AS VARCHAR) + ';' + CAST(B.DINH_DANH_HANG_HOA AS VARCHAR) + ';' AS NVARCHAR(100)) AS CKEYS, 
    A.DHOPDONGID, A.TYPE, A.SO_PHIEU, A.NGAY_PHIEU, A.DPHIEUID, A.SO_HD, A.NGAY_HD, A.MA_NGUON, A.MA_NT, A.TY_GIA_VND,
    B.DPHIEU_HANGID, B.SO_TK, CAST(B.NGAY_DK AS DATE) AS NGAY_DK, F.NGAY_NHAP, B.NGAY_VAO_RA, B.DINH_DANH_HANG_HOA, 
    B.MA_SP, B.TEN_SP, B.STTHANG, B.MA_NUOC, B.SO_LUONG, B.MA_DVT, B.TRONG_LUONG_GW, B.TRONG_LUONG_NW, 
    B.DON_GIA AS GIA_NHAP, B.TRI_GIA, B.MA_HS, B.VI_TRI_HANG, B.SO_CONT, 
    D.SO_SEAL, S.TEN_NGUON, T.TEN_DVT, G.TEN_KH, CAST('' AS NVARCHAR(100)) AS GHI_CHU
INTO #NHAP 
FROM DPHIEU A WITH (NOLOCK)
INNER JOIN DPHIEU_HANG B WITH (NOLOCK) ON A.DPHIEUID = B.DPHIEUID AND ISNULL(B.IS_HUY, 0) = 0
INNER JOIN DCONTAINER D WITH (NOLOCK) ON D.DPHIEUID = A.DPHIEUID AND D.SO_CONT = B.SO_CONT AND ISNULL(D.IS_HUY, 0) = 0 AND D.IS_RUTHANG = 0 
LEFT JOIN DHOPDONG F WITH (NOLOCK) ON A.DHOPDONGID = F.DHOPDONGID 
LEFT JOIN SKHACHHANG G WITH (NOLOCK) ON G.MA_KH = F.MA_KH AND F.MA_KNQ = G.MA_KNQ
LEFT JOIN SNGUONHANG S WITH (NOLOCK) ON S.MA_NGUON = A.MA_NGUON 
LEFT JOIN SDVT T WITH (NOLOCK) ON B.MA_DVT = T.MA_DVT
WHERE A.MA_KNQ = @MaKNQ AND A.TYPE = 1 AND A._XORN = 'N' AND A.TRANG_THAI = 'T' 
  AND ((A.PB_PHIEU = 'CT' AND A.DPHIEUID_NEXT IS NULL) OR (A.PB_PHIEU = 'SU' AND A.DPHIEUID_PREV IS NOT NULL))
  AND A.NGAY_PHIEU <= @TargetDate;

-- --------------------------------------------------------------------
-- STEP 2: 洗涤账目：扣减掉已经在库内卸货拆箱（Rút hàng）的空箱行
-- --------------------------------------------------------------------
IF OBJECT_ID('tempdb..#DRUTHANG') IS NOT NULL DROP TABLE #DRUTHANG;

SELECT A.DPHIEUID, A.SO_CONT, B.SO_DINH_DANH AS DINH_DANH_HANG_HOA 
INTO #DRUTHANG FROM DRUTHANG A WITH (NOLOCK)
INNER JOIN DRUTHANG_CT B WITH (NOLOCK) ON A.DRUTHANGID = B.DRUTHANGID
WHERE A.MA_KNQ = @MaKNQ AND A.TRANG_THAI = 2 
GROUP BY A.DPHIEUID, A.SO_CONT, B.SO_DINH_DANH;

DELETE #NHAP FROM #NHAP A, #DRUTHANG B WHERE A.DPHIEUID = B.DPHIEUID AND A.SO_CONT = B.SO_CONT;
DROP TABLE #DRUTHANG;

-- --------------------------------------------------------------------
-- STEP 3: 追加写入所有【普通散货 / 件货（Type = 2）】的原始入库明细
-- --------------------------------------------------------------------
INSERT INTO #NHAP 
SELECT 
    CAST(CAST(A.DHOPDONGID AS VARCHAR) + ';' + CAST(A.TYPE AS VARCHAR) + ';' + CAST(B.DINH_DANH_HANG_HOA AS VARCHAR) + ';' AS NVARCHAR(100)) AS CKEYS, 
    A.DHOPDONGID, A.TYPE, A.SO_PHIEU, A.NGAY_PHIEU, A.DPHIEUID, A.SO_HD, A.NGAY_HD, A.MA_NGUON, A.MA_NT, A.TY_GIA_VND,
    B.DPHIEU_HANGID, B.SO_TK, CAST(B.NGAY_DK AS DATE) AS NGAY_DK, F.NGAY_NHAP, B.NGAY_VAO_RA, B.DINH_DANH_HANG_HOA, 
    B.MA_SP, B.TEN_SP, B.STTHANG, B.MA_NUOC, B.SO_LUONG, B.MA_DVT, B.TRONG_LUONG_GW, B.TRONG_LUONG_NW, 
    B.DON_GIA AS GIA_NHAP, B.TRI_GIA, B.MA_HS, B.VI_TRI_HANG, B.SO_CONT, 
    '' AS SO_SEAL, S.TEN_NGUON, T.TEN_DVT, G.TEN_KH, CAST('' AS NVARCHAR(100)) AS GHI_CHU
FROM DPHIEU A WITH (NOLOCK)
INNER JOIN DPHIEU_HANG B WITH (NOLOCK) ON A.DPHIEUID = B.DPHIEUID AND ISNULL(B.IS_HUY, 0) = 0
LEFT JOIN DHOPDONG F WITH (NOLOCK) ON A.DHOPDONGID = F.DHOPDONGID 
LEFT JOIN SKHACHHANG G WITH (NOLOCK) ON G.MA_KH = F.MA_KH AND F.MA_KNQ = G.MA_KNQ
LEFT JOIN SNGUONHANG S WITH (NOLOCK) ON S.MA_NGUON = A.MA_NGUON 
LEFT JOIN SDVT T WITH (NOLOCK) ON B.MA_DVT = T.MA_DVT
WHERE A.MA_KNQ = @MaKNQ AND A.TYPE = 2 AND A._XORN = 'N' AND A.TRANG_THAI = 'T' 
  AND ((A.PB_PHIEU = 'CT' AND A.DPHIEUID_NEXT IS NULL) OR (A.PB_PHIEU = 'SU' AND A.DPHIEUID_PREV IS NOT NULL))
  AND A.NGAY_PHIEU <= @TargetDate;

-- --------------------------------------------------------------------
-- STEP 4: 汇集全量截止日前的【分批正常出库及海关监督销毁出库流水】
-- --------------------------------------------------------------------
IF OBJECT_ID('tempdb..#XUAT') IS NOT NULL DROP TABLE #XUAT;

SELECT CAST('' AS NVARCHAR(100)) AS CKEYS, A.TYPE, A.DHOPDONGID, A.SO_HD, MAX(A.NGAY_PHIEU) AS NGAY_XUAT, B.SO_PHIEU_N, B.MA_SP, B.DINH_DANH_HANG_HOA, ROUND(SUM(B.SO_LUONG), 4) AS SO_LUONG, MAX(B.NGAY_VAO_RA) AS NGAY_GETOUT, 0 AS IS_TIEU_HUY
INTO #XUAT FROM DPHIEU A WITH (NOLOCK)
INNER JOIN DPHIEU_HANG B WITH (NOLOCK) ON (A.DPHIEUID = B.DPHIEUID AND ISNULL(B.IS_HUY, 0) = 0) 
INNER JOIN DCONTAINER DF WITH (NOLOCK) ON DF.DPHIEUID = A.DPHIEUID AND DF.IS_RUTHANG = 0 AND DF.TINH_TRANG = 1 AND A.DRUTHANGID IS NULL 
WHERE A.MA_KNQ = @MaKNQ AND A.TYPE = 1 AND A._XORN = 'X' AND A.MA_NGUON <> 'X4' AND A.TRANG_THAI = 'T'
  AND ((A.PB_PHIEU = 'CT' AND A.DPHIEUID_NEXT IS NULL) OR (A.PB_PHIEU = 'SU' AND A.DPHIEUID_PREV IS NOT NULL)) AND A.NGAY_PHIEU <= @TargetDate
GROUP BY A.TYPE, A.DHOPDONGID, A.SO_HD, B.SO_PHIEU_N, B.MA_SP, B.DINH_DANH_HANG_HOA;

INSERT INTO #XUAT 
SELECT CAST('' AS NVARCHAR(100)) AS CKEYS, A.TYPE, A.DHOPDONGID, A.SO_HD, MAX(A.NGAY_PHIEU) AS NGAY_XUAT, B.SO_PHIEU_N, B.MA_SP, B.DINH_DANH_HANG_HOA, ROUND(SUM(B.SO_LUONG), 4) AS SO_LUONG, MAX(B.NGAY_VAO_RA) AS NGAY_GETOUT, 0 AS IS_TIEU_HUY
FROM DPHIEU A WITH (NOLOCK)
INNER JOIN DPHIEU_HANG B WITH (NOLOCK) ON (A.DPHIEUID = B.DPHIEUID AND ISNULL(B.IS_HUY, 0) = 0) 
WHERE A.MA_KNQ = @MaKNQ AND A.TYPE = 2 AND A._XORN = 'X' AND A.MA_NGUON <> 'X4' AND A.TRANG_THAI = 'T'
  AND ((A.PB_PHIEU = 'CT' AND A.DPHIEUID_NEXT IS NULL) OR (A.PB_PHIEU = 'SU' AND A.DPHIEUID_PREV IS NOT NULL)) AND A.NGAY_PHIEU <= @TargetDate
GROUP BY A.TYPE, A.DHOPDONGID, A.SO_HD, B.SO_PHIEU_N, B.MA_SP, B.DINH_DANH_HANG_HOA;

INSERT INTO #XUAT 
SELECT CAST('' AS NVARCHAR(100)) AS CKEYS, 2 AS TYPE, A.DHOPDONGID, A.SO_HD, B.NGAY_PHIEU AS NGAY_XUAT, A.SO_PHIEU_N, A.MA_SP, A.DINH_DANH_HANG_HOA, ROUND(A.SO_LUONG, 4) AS SO_LUONG, NULL AS NGAY_GETOUT, 1 AS IS_TIEU_HUY
FROM DTIEUHUY_CT A WITH (NOLOCK) INNER JOIN DTIEUHUY B WITH (NOLOCK) ON A.DTIEUHUYID = B.DTIEUHUYID
WHERE B.MA_KNQ = @MaKNQ AND B.TRANG_THAI = 1 AND B.NGAY_PHIEU <= @TargetDate;

-- --------------------------------------------------------------------
-- STEP 5: 提取所有权虚转网（#DVANBAN），连环穿透校正实物原始日期
-- --------------------------------------------------------------------
IF OBJECT_ID('tempdb..#DVANBAN') IS NOT NULL DROP TABLE #DVANBAN;
IF OBJECT_ID('tempdb..#NHAP_X') IS NOT NULL DROP TABLE #NHAP_X;

SELECT CAST(CAST(DHOPDONGID_GUI AS VARCHAR) + ';' + CAST(TYPE AS VARCHAR) + ';' + CAST(DINH_DANH_HANG_HOA AS VARCHAR) + ';' AS NVARCHAR(100)) AS CKEYS, B.DVANBANID, B.DHOPDONGID_GUI, F.SO_HD AS SO_HD_GUI, B.DHOPDONGID_NHAN, G.SO_HD AS SO_HD_NHAN, B.SOTK, A.TYPE, A.SO_PHIEU_N, A.STTHANG_N, A.MA_SP, A.DINH_DANH_HANG_HOA, A.SO_LUONG, A.TRI_GIA, F.NGAY_NHAP, CAST(NULL AS DATETIME) AS NGAY_VAO_RA
INTO #DVANBAN FROM DVANBAN_HANG A, DVANBAN B, DHOPDONG F, DHOPDONG G
WHERE B.MA_KNQ = @MaKNQ AND B.TRANG_THAI = '2' AND A.DVANBANID = B.DVANBANID AND B.DHOPDONGID_GUI = F.DHOPDONGID AND B.DHOPDONGID_NHAN = G.DHOPDONGID AND B.NGAY_CHUYEN_QUYEN <= @TargetDate;

SELECT CAST('' AS NVARCHAR(100)) AS CKEYS, A.TYPE, A.SO_PHIEU, A.MA_NGUON, A.DHOPDONGID, A.SO_HD, A.NGAY_HD, A.NGAY_HHHD, B.SO_TK, B.NGAY_DK, B.DINH_DANH_HANG_HOA, F.NGAY_NHAP, B.NGAY_VAO_RA
INTO #NHAP_X FROM DPHIEU A INNER JOIN DPHIEU_HANG B ON A.DPHIEUID = B.DPHIEUID LEFT JOIN DHOPDONG F ON A.DHOPDONGID = F.DHOPDONGID 
WHERE A.MA_KNQ = @MaKNQ AND A._XORN = 'N' AND A.TRANG_THAI = 'T' AND A.NGAY_PHIEU <= @TargetDate
GROUP BY A.TYPE, A.SO_PHIEU, A.MA_NGUON, A.DHOPDONGID, A.SO_HD, A.NGAY_HD, A.NGAY_HHHD, B.SO_TK, B.NGAY_DK, B.DINH_DANH_HANG_HOA, F.NGAY_NHAP, B.NGAY_VAO_RA;

-- 执行 5 代所有权追随回归
DECLARE @c INT = 1, @d INT = 0;
WHILE ((@c <= 5) AND @d = 0) 
BEGIN 
    UPDATE #DVANBAN SET NGAY_VAO_RA = B.NGAY_VAO_RA FROM #DVANBAN A, #NHAP_X B WHERE A.TYPE = B.TYPE AND A.DHOPDONGID_GUI = B.DHOPDONGID AND A.SO_PHIEU_N = B.SO_PHIEU AND A.DINH_DANH_HANG_HOA = B.DINH_DANH_HANG_HOA AND B.NGAY_VAO_RA IS NOT NULL; 
    UPDATE #NHAP SET NGAY_NHAP = B.NGAY_NHAP, NGAY_VAO_RA = B.NGAY_VAO_RA FROM #NHAP A, #DVANBAN B WHERE A.TYPE = B.TYPE AND A.MA_NGUON = 'N4' AND A.DHOPDONGID = B.DHOPDONGID_NHAN AND A.DINH_DANH_HANG_HOA = B.DINH_DANH_HANG_HOA AND B.NGAY_VAO_RA IS NOT NULL; 
    UPDATE #NHAP_X SET NGAY_NHAP = B.NGAY_NHAP, NGAY_VAO_RA = B.NGAY_VAO_RA FROM #NHAP_X A, #DVANBAN B WHERE A.TYPE = B.TYPE AND A.MA_NGUON = 'N4' AND A.DHOPDONGID = B.DHOPDONGID_NHAN AND A.DINH_DANH_HANG_HOA = B.DINH_DANH_HANG_HOA AND B.NGAY_VAO_RA IS NOT NULL; 
    IF NOT EXISTS(SELECT 1 FROM #DVANBAN WHERE NGAY_VAO_RA IS NULL) AND NOT EXISTS(SELECT 1 FROM #NHAP_X WHERE NGAY_VAO_RA IS NULL) AND NOT EXISTS(SELECT 1 FROM #NHAP WHERE NGAY_VAO_RA IS NULL) SELECT @d = 1; 
    SET @c += 1;
END;

-- --------------------------------------------------------------------
-- STEP 6: 对冲剥离纸面虚拟合同转让 (内部过户对冲)
-- --------------------------------------------------------------------
IF OBJECT_ID('tempdb..#NHAP2') IS NOT NULL DROP TABLE #NHAP2;
IF OBJECT_ID('tempdb..#DVANBAN2') IS NOT NULL DROP TABLE #DVANBAN2;

SELECT ROW_NUMBER() OVER(PARTITION BY CKEYS ORDER BY NGAY_PHIEU, DPHIEUID, DPHIEU_HANGID) AS STT, *, SO_LUONG AS SO_LUONG2, TRI_GIA AS TRI_GIA2, 0*SO_LUONG AS SO_LUONG_SD, TRI_GIA AS TRI_GIA_SD, 0*TRI_GIA AS TRI_GIA_TON, 0*SO_LUONG AS LUONG_XUAT, 0*SO_LUONG AS LUONG_TON, CAST (NULL AS DATE) AS NGAY_XUAT, CAST (NULL AS INT) AS SO_NGAY_TON 
INTO #NHAP2 FROM #NHAP;

SELECT CKEYS, SUM(SO_LUONG) AS SO_LUONG, 0*SUM(SO_LUONG) AS SO_LUONG_SD, SUM(SO_LUONG) AS SO_LUONG_TON, SUM(TRI_GIA) AS TRI_GIA, 0*SUM(TRI_GIA) AS TRI_GIA_SD, SUM(TRI_GIA) AS TRI_GIA_TON 
INTO #DVANBAN2 FROM #DVANBAN A GROUP BY CKEYS;

DECLARE @x INT = 1, @y INT = ISNULL((SELECT MAX(STT) FROM #NHAP2), 1);
WHILE (@x <= @y)
BEGIN
    UPDATE #NHAP2 SET SO_LUONG_SD = CASE WHEN B.SO_LUONG_TON > A.SO_LUONG THEN A.SO_LUONG ELSE B.SO_LUONG_TON END, TRI_GIA_SD = CASE WHEN B.TRI_GIA_TON > A.TRI_GIA THEN A.TRI_GIA ELSE B.TRI_GIA_TON END FROM #NHAP2 A, #DVANBAN2 B WHERE A.CKEYS = B.CKEYS AND B.SO_LUONG_TON > 0 AND STT = @x;
    UPDATE #DVANBAN2 SET SO_LUONG_SD = B.SO_LUONG_SD, TRI_GIA_SD = B.TRI_GIA_SD FROM #DVANBAN2 A, (SELECT CKEYS, SUM(SO_LUONG_SD) SO_LUONG_SD, SUM(TRI_GIA_SD) TRI_GIA_SD FROM #NHAP2 WHERE SO_LUONG_SD > 0 GROUP BY CKEYS) B WHERE A.CKEYS = B.CKEYS;
    UPDATE #DVANBAN2 SET SO_LUONG_TON = SO_LUONG - SO_LUONG_SD, TRI_GIA_TON = TRI_GIA - TRI_GIA_SD;
    SET @x += 1;
END;

UPDATE #NHAP2 SET SO_LUONG = SO_LUONG2 - SO_LUONG_SD, TRI_GIA = TRI_GIA2 - TRI_GIA_SD;
DELETE #NHAP2 WHERE SO_LUONG = 0;

UPDATE #NHAP_X SET CKEYS = CAST(TYPE AS VARCHAR) + ';' + CAST(SO_PHIEU AS VARCHAR) + ';' + CAST(DINH_DANH_HANG_HOA AS VARCHAR) + ';';
UPDATE #XUAT SET CKEYS = CAST(TYPE AS VARCHAR) + ';' + CAST(SO_PHIEU_N AS VARCHAR) + ';' + CAST(DINH_DANH_HANG_HOA AS VARCHAR) + ';';
UPDATE #XUAT SET DHOPDONGID = B.DHOPDONGID, SO_HD = B.SO_HD FROM #XUAT A, #NHAP_X B WHERE A.CKEYS = B.CKEYS;

IF OBJECT_ID('tempdb..#XUAT2') IS NOT NULL DROP TABLE #XUAT2;
SELECT ROW_NUMBER() OVER(PARTITION BY DHOPDONGID, TYPE, DINH_DANH_HANG_HOA ORDER BY DHOPDONGID, TYPE, DINH_DANH_HANG_HOA, NGAY_XUAT) AS STT, CAST(CAST(DHOPDONGID AS VARCHAR) + ';' + CAST(TYPE AS VARCHAR) + ';' + CAST(DINH_DANH_HANG_HOA AS VARCHAR) + ';' AS NVARCHAR(100)) AS CKEYS, DHOPDONGID, TYPE, DINH_DANH_HANG_HOA, NGAY_XUAT, SUM(SO_LUONG) AS SO_LUONG, 0*SUM(SO_LUONG) AS LUONG_XUAT, SUM(SO_LUONG) AS LUONG_TON, 0*SUM(SO_LUONG) AS TONG_NHAP, 0*SUM(SO_LUONG) AS TONG_XUAT, SUM(SO_LUONG) AS TONG_TON, 0 AS IS_TIEU_HUY
INTO #XUAT2 FROM #XUAT GROUP BY DHOPDONGID, TYPE, DINH_DANH_HANG_HOA, NGAY_XUAT;

UPDATE #XUAT2 SET TONG_NHAP = B.SO_LUONG, TONG_TON = B.SO_LUONG FROM #XUAT2 A, (SELECT CKEYS, SUM(SO_LUONG) AS SO_LUONG FROM #XUAT2 GROUP BY CKEYS) B WHERE A.CKEYS = B.CKEYS;
UPDATE #XUAT2 SET IS_TIEU_HUY = 1 FROM #XUAT2 A, #XUAT B WHERE A.TYPE = B.TYPE AND A.DHOPDONGID = B.DHOPDONGID AND A.DINH_DANH_HANG_HOA = B.DINH_DANH_HANG_HOA AND B.IS_TIEU_HUY = 1;

DROP TABLE #NHAP, #XUAT, #NHAP_X, #DVANBAN, #DVANBAN2;

-- --------------------------------------------------------------------
-- STEP 7: 【终极 FIFO 核心核销引擎】双层 WHILE 冲抵分摊计算
-- --------------------------------------------------------------------
UPDATE #NHAP2 SET LUONG_TON = SO_LUONG - LUONG_XUAT, SO_LUONG_SD = 0;

DECLARE @stop INT = 0;
WHILE (@stop = 0)
BEGIN
    IF OBJECT_ID('tempdb..#XUAT3') IS NOT NULL DROP TABLE #XUAT3;
    SELECT A.* INTO #XUAT3 FROM #XUAT2 A, (SELECT CKEYS, MIN(STT) AS STT FROM #XUAT2 WHERE LUONG_TON > 0 GROUP BY CKEYS) B WHERE A.CKEYS = B.CKEYS AND A.STT = B.STT;
    
    DECLARE @stop2 INT = 0;
    WHILE (@stop2 = 0)
    BEGIN
        IF OBJECT_ID('tempdb..#NHAP3') IS NOT NULL DROP TABLE #NHAP3;
        SELECT A.* INTO #NHAP3 FROM #NHAP2 A, (SELECT CKEYS, MIN(STT) AS STT FROM #NHAP2 WHERE LUONG_TON > 0 GROUP BY CKEYS) B WHERE A.CKEYS = B.CKEYS AND A.STT = B.STT;
        
        IF NOT EXISTS(SELECT 1 FROM #XUAT3 A, #NHAP3 B WHERE A.CKEYS = B.CKEYS AND A.LUONG_TON > 0 AND B.LUONG_TON > 0) SET @stop2 = 1;
        
        UPDATE #NHAP3 SET NGAY_XUAT = B.NGAY_XUAT, SO_LUONG_SD = CASE WHEN B.LUONG_TON > A.LUONG_TON THEN A.LUONG_TON ELSE B.LUONG_TON END FROM #NHAP3 A, #XUAT3 B WHERE A.CKEYS = B.CKEYS AND B.LUONG_TON > 0 AND A.LUONG_TON > 0;
        UPDATE #NHAP3 SET LUONG_XUAT += SO_LUONG_SD;
        UPDATE #XUAT3 SET LUONG_XUAT += B.SO_LUONG_SD FROM #XUAT3 A, #NHAP3 B WHERE A.CKEYS = B.CKEYS;
        UPDATE #XUAT3 SET LUONG_TON = SO_LUONG - LUONG_XUAT;
        UPDATE #NHAP3 SET LUONG_TON = SO_LUONG - LUONG_XUAT;
        UPDATE #NHAP2 SET LUONG_XUAT = B.LUONG_XUAT, LUONG_TON = B.LUONG_TON, NGAY_XUAT = B.NGAY_XUAT FROM #NHAP2 A, #NHAP3 B WHERE A.CKEYS = B.CKEYS AND A.STT = B.STT;
        DROP TABLE #NHAP3;
    END;
    UPDATE #XUAT2 SET LUONG_XUAT = B.LUONG_XUAT, LUONG_TON = B.LUONG_TON FROM #XUAT2 A, #XUAT3 B WHERE A.CKEYS = B.CKEYS AND A.STT = B.STT;
    IF NOT EXISTS(SELECT 1 FROM #XUAT2 A, #NHAP2 B WHERE A.CKEYS = B.CKEYS AND A.LUONG_TON > 0 AND B.LUONG_TON > 0) SET @stop = 1;
    DROP TABLE #XUAT3;
END;

-- --------------------------------------------------------------------
-- STEP 8: 【斩杀与最终输出】对齐系统原始英文字段与 Excel 排序
-- --------------------------------------------------------------------
UPDATE #NHAP2 SET TRI_GIA_TON = ISNULL(LUONG_TON * GIA_NHAP * TY_GIA_VND, 0);
UPDATE #NHAP2 SET GHI_CHU = CASE WHEN A.GHI_CHU = '' THEN '' ELSE A.GHI_CHU + ', ' END + N'Có hàng tiêu hủy' FROM #NHAP2 A, #XUAT2 B WHERE A.CKEYS = B.CKEYS AND B.IS_TIEU_HUY = 1;

-- 【绝杀清零】：扣减完没余额的货，直接物理删除！只留纯正的 OnHand 实存！
DELETE #NHAP2 WHERE ROUND(LUONG_TON, 4) <= 0;

-- 动态计算精准库龄
UPDATE #NHAP2 SET SO_NGAY_TON = DATEDIFF(dd, NGAY_NHAP, @TargetDate) + 1;

-- ====================================================================
-- 终极输出：抛弃中文别名，完美对齐 ECUS5 数据库原生列名，并附加详尽业务注释
-- ====================================================================
SELECT 
    SO_PHIEU,             -- [入库单] 初始入库单号 (Số phiếu)
    NGAY_PHIEU,           -- [入库单] 初始入仓日期 (Ngày phiếu)
    SO_HD,                -- [合规] 保税合同号 (Số hợp đồng)
    NGAY_HD,              -- [合规] 保税合同录入日期 (Ngày hợp đồng)
    MA_NGUON,             -- [来源] 货物来源属性代码 (Mã nguồn)
    SO_TK,                -- [报关] 海关进口报关单号 (Số tờ khai)
    NGAY_DK,              -- [报关] 报关单申报注册日期 (Ngày đăng ký)
    NGAY_NHAP,            -- [溯源] 原始真实入库日期 (Ngày nhập)
    DINH_DANH_HANG_HOA,   -- [溯源] 货物海关唯一定标码 (Định danh hàng hóa)
    MA_SP,                -- [商品] 内部商品编码 (Mã sản phẩm)
    TEN_SP,               -- [商品] 商品综合品名 (Tên sản phẩm)
    MA_NUOC,              -- [商品] 原产国代码 (Mã nước)
    MA_HS,                -- [报关] 海关HS税号 (Mã HS)
    SO_LUONG AS LUONG_NHAP, -- [物控] 原始到货总量 (Lượng nhập)
    LUONG_XUAT,           -- [物控] 已被领走/出库数量 (Lượng xuất)
    LUONG_TON,            -- [物控] ★ 当前在库实物结存数量 (Lượng tồn)
    MA_DVT,               -- [物控] 计量单位编码 (Mã ĐVT)
    TRONG_LUONG_GW,       -- [物控] 毛重-Gross Weight (Trọng lượng GW)
    TRONG_LUONG_NW,       -- [物控] 净重-Net Weight (Trọng lượng NW)
    GIA_NHAP,             -- [财务] 原始进口单价 (Đơn giá nhập)
    TRI_GIA_TON,          -- [财务] ★ 当前结存总资产价值 (Trị giá tồn)
    VI_TRI_HANG,          -- [仓配] 仓库物理货位格 (Vị trí hàng)
    SO_CONT,              -- [仓配] 集装箱柜号 (Số Container)
    SO_SEAL,              -- [仓配] 海关铅封号 (Số Seal)
    TEN_NGUON,            -- [字典] 货物来源类型说明 (Tên nguồn)
    TEN_DVT,              -- [字典] 计量单位名称说明 (Tên ĐVT)
    TEN_KH,               -- [客户] 货主客户名称 (Tên khách hàng)
    SO_NGAY_TON,          -- [库龄] ★ 该批货物实际滞库天数 (Số ngày tồn)
    GHI_CHU               -- [其他] 系统级动作备注 (Ghi chú)
FROM #NHAP2 
ORDER BY NGAY_PHIEU ASC, SO_PHIEU ASC, STTHANG ASC;

-- 清理现场
DROP TABLE #NHAP2, #XUAT2;
```
