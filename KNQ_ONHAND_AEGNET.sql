-- 修正版：针对 ECUS5_KNQ 数据库的库存查询
-- 错误原因：明细表中的报关单号字段应为 SO_TK

SELECT 
    ROW_NUMBER() OVER(ORDER BY PH.NGAY_DK DESC, PH.SO_TK) AS STT, -- 序号
    PH.SO_TK AS [Số TK nhập],               -- 修正字段名：报关单号
    PH.NGAY_DK AS [Ngày TK],                -- 报关日期
    P.SO_PHIEU AS [Số PNK],                 -- 入库单号 (Header)
    P.NGAY_PHIEU AS [Ngày NK],              -- 入库日期
    P.SO_HD AS [Số hợp đồng],               -- 合同号[cite: 1]
    P.NGAY_HD AS [Ngày hợp đồng],           -- 合同日期[cite: 1]
    PH.MA_SP AS [Mã hàng],                  -- 商品编码[cite: 1]
    PH.TEN_SP AS [Tên hàng],                -- 商品名称[cite: 1]
    PH.DINH_DANH_HANG_HOA AS [Định danh],   -- 商品标识[cite: 1]
    PH.MA_HS AS [Mã HS],                    -- HS编码[cite: 1]
    PH.MA_NUOC AS [Xuất xứ],                -- 原产国[cite: 1]
    PH.SO_LUONG AS [Lượng nhập],            -- 原始入库数量[cite: 1]
    PH.DON_GIA AS [Đơn giá],                -- 单价[cite: 1]
    PH.MA_DVT AS [Đơn vị tính],             -- 单位[cite: 1]
    
    -- 计算已核销/出库数量 (基于关联字段 SO_PHIEU_N 和 STTHANG_N)
    ISNULL((SELECT SUM(X.SO_LUONG) 
            FROM DPHIEU_HANG X 
            WHERE X.SO_PHIEU_N = PH.SO_PHIEU_N 
              AND X.STTHANG_N = PH.STTHANG 
              AND X.IS_XUAT = 1), 0) AS [Lượng xuất], -- 已出库数量[cite: 1]
              
    -- 计算库存结余
    (PH.SO_LUONG - ISNULL((SELECT SUM(X.SO_LUONG) 
                           FROM DPHIEU_HANG X 
                           WHERE X.SO_PHIEU_N = PH.SO_PHIEU_N 
                             AND X.STTHANG_N = PH.STTHANG 
                             AND X.IS_XUAT = 1), 0)) AS [SL Tồn], -- 库存余量
                             
    P.MA_NT AS [Mã NT]                      -- 币种[cite: 1]
FROM 
    DPHIEU_HANG PH WITH (NOLOCK)
INNER JOIN 
    DPHIEU P WITH (NOLOCK) ON PH.DPHIEUID = P.DPHIEUID
WHERE 
    P._XORN = 'N'                          -- 筛选入库单据[cite: 1]
    AND PH.IS_XUAT = 0                      -- 筛选原始入库明细行[cite: 1]
    -- 过滤掉已经完全核销（库存为0）的记录
    AND (PH.SO_LUONG - ISNULL((SELECT SUM(X.SO_LUONG) 
                               FROM DPHIEU_HANG X 
                               WHERE X.SO_PHIEU_N = PH.SO_PHIEU_N 
                                 AND X.STTHANG_N = PH.STTHANG 
                                 AND X.IS_XUAT = 1), 0)) > 0
ORDER BY 
    PH.NGAY_DK DESC;