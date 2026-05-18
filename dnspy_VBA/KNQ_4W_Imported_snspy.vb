Sub a002_KNQ_4W_IMPORTED_SQLSERVER_()
    ' Declare the variables
    Dim connection As Object
    Dim rs As Object
    Dim sql_query As String
    Dim excel_ws As Worksheet
    Dim arr As Variant
    Dim arrT() As Variant
    Dim i As Long, j As Long
    Dim fieldCount As Integer
    Dim startdate As String
    Dim enddate As String
    Dim rawStart As String
    Dim rawEnd As String
    Dim rowCount As Long
    Dim colCount As Long

    ' 初始化数据库连接参数
    Dim server_name As String
    Dim database_name As String
    server_name = "VPHUVNVPSQ23267"
    database_name = "ECUS5_KNQ"

    ' ★ 防弹清洗机制：获取日期并剔除潜伏的单/双引号
    rawStart = Replace(Replace(Sheet25.Range("C2").Value, "'", ""), """", "")
    rawEnd = Replace(Replace(Sheet25.Range("C3").Value, "'", ""), """", "")

    ' 强制格式化为 SQL 认识的标准格式 yyyy-MM-dd
    startdate = Format(rawStart, "yyyy-MM-dd")
    enddate = Format(rawEnd, "yyyy-MM-dd")

    ' =========================================================================
    ' 构造终极精准版 KNQ_4W_IMPORTED SQL 脚本 (包含掏箱与过户额度核销算法)
    ' =========================================================================
    sql_query = ""
    sql_query = sql_query & "SET NOCOUNT ON; " & vbCrLf
    sql_query = sql_query & "SET ANSI_WARNINGS OFF; " & vbCrLf
    sql_query = sql_query & "SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED; " & vbCrLf

    sql_query = sql_query & "DECLARE @MaKNQ NVARCHAR(50) = 'VNNSL'; " & vbCrLf
    sql_query = sql_query & "DECLARE @StartDate DATETIME = '" & startdate & "'; " & vbCrLf
    sql_query = sql_query & "DECLARE @EndDate DATETIME = '" & enddate & "'; " & vbCrLf

    ' STEP 1: 提取所有【集装箱重箱（Type = 1）】的正式生效入库流水
    sql_query = sql_query & "IF OBJECT_ID('tempdb..#NHAP') IS NOT NULL DROP TABLE #NHAP; " & vbCrLf
    sql_query = sql_query & "SELECT CAST(CAST(A.DHOPDONGID AS VARCHAR) + ';' + CAST(A.TYPE AS VARCHAR) + ';' + CAST(B.DINH_DANH_HANG_HOA AS VARCHAR) + ';' AS NVARCHAR(100)) AS CKEYS, "
    sql_query = sql_query & "A.DHOPDONGID, A.TYPE, A.SO_PHIEU, A.NGAY_PHIEU, A.DPHIEUID, A.SO_HD, A.NGAY_HD, A.MA_NGUON, A.SO_BBBG, A.SO_CHUNG_TU, A.TEN_NGUOI_GIAO_HANG, A.TONG_SO_KIEN, "
    sql_query = sql_query & "B.DPHIEU_HANGID, B.SO_TK, CAST(B.NGAY_DK AS DATE) AS NGAY_DK, B.DINH_DANH_HANG_HOA, B.MA_SP, B.TEN_SP, B.STTHANG, B.MA_NUOC, B.SO_LUONG, B.MA_DVT, B.TRONG_LUONG_GW, B.TRONG_LUONG_NW, "
    sql_query = sql_query & "B.DON_GIA AS GIA_NHAP, B.TRI_GIA, B.MA_HS, B.VI_TRI_HANG, B.SO_CONT, "
    sql_query = sql_query & "D.SO_SEAL, S.TEN_NGUON, T.TEN_DVT, G.TEN_KH, "
    sql_query = sql_query & "CAST('' AS NVARCHAR(100)) AS GHI_CHU, B.GHI_CHU AS GHI_CHU_HANG, B.SO_QUAN_LY "
    sql_query = sql_query & "INTO #NHAP FROM DPHIEU A WITH (NOLOCK) "
    sql_query = sql_query & "INNER JOIN DPHIEU_HANG B WITH (NOLOCK) ON A.DPHIEUID = B.DPHIEUID AND ISNULL(B.IS_HUY, 0) = 0 "
    sql_query = sql_query & "INNER JOIN DCONTAINER D WITH (NOLOCK) ON D.DPHIEUID = A.DPHIEUID AND D.SO_CONT = B.SO_CONT AND ISNULL(D.IS_HUY, 0) = 0 "
    sql_query = sql_query & "LEFT JOIN DHOPDONG F WITH (NOLOCK) ON A.DHOPDONGID = F.DHOPDONGID "
    sql_query = sql_query & "LEFT JOIN SKHACHHANG G WITH (NOLOCK) ON G.MA_KH = F.MA_KH AND F.MA_KNQ = G.MA_KNQ "
    sql_query = sql_query & "LEFT JOIN SNGUONHANG S WITH (NOLOCK) ON S.MA_NGUON = A.MA_NGUON "
    sql_query = sql_query & "LEFT JOIN SDVT T WITH (NOLOCK) ON B.MA_DVT = T.MA_DVT "
    sql_query = sql_query & "WHERE A.MA_KNQ = @MaKNQ AND A.TYPE = 1 AND A._XORN = 'N' AND A.TRANG_THAI = 'T' "
    sql_query = sql_query & "AND ((A.PB_PHIEU = 'CT' AND A.DPHIEUID_NEXT IS NULL) OR (A.PB_PHIEU = 'SU' AND A.DPHIEUID_PREV IS NOT NULL)) "
    sql_query = sql_query & "AND A.NGAY_PHIEU >= @StartDate AND A.NGAY_PHIEU <= @EndDate; " & vbCrLf

    ' STEP 2: 【去重排除】扣减剔除掉在库内已经办理了“掏箱落地”的重箱流水
    sql_query = sql_query & "IF OBJECT_ID('tempdb..#DRUTHANG') IS NOT NULL DROP TABLE #DRUTHANG; " & vbCrLf
    sql_query = sql_query & "SELECT A.DPHIEUID, A.SO_CONT, B.SO_DINH_DANH AS DINH_DANH_HANG_HOA INTO #DRUTHANG FROM DRUTHANG A WITH (NOLOCK) "
    sql_query = sql_query & "INNER JOIN DRUTHANG_CT B WITH (NOLOCK) ON A.DRUTHANGID = B.DRUTHANGID "
    sql_query = sql_query & "WHERE A.MA_KNQ = @MaKNQ AND A.TRANG_THAI = 2 GROUP BY A.DPHIEUID, A.SO_CONT, B.SO_DINH_DANH; " & vbCrLf
    sql_query = sql_query & "DELETE #NHAP FROM #NHAP A, #DRUTHANG B WHERE A.DPHIEUID = B.DPHIEUID AND A.SO_CONT = B.SO_CONT; " & vbCrLf
    sql_query = sql_query & "DROP TABLE #DRUTHANG; " & vbCrLf

    ' STEP 3: 追加写入所有【普通散货 / 件货（Type = 2）】的正式生效入库明细
    sql_query = sql_query & "INSERT INTO #NHAP SELECT CAST(CAST(A.DHOPDONGID AS VARCHAR) + ';' + CAST(A.TYPE AS VARCHAR) + ';' + CAST(B.DINH_DANH_HANG_HOA AS VARCHAR) + ';' AS NVARCHAR(100)) AS CKEYS, "
    sql_query = sql_query & "A.DHOPDONGID, A.TYPE, A.SO_PHIEU, A.NGAY_PHIEU, A.DPHIEUID, A.SO_HD, A.NGAY_HD, A.MA_NGUON, A.SO_BBBG, A.SO_CHUNG_TU, A.TEN_NGUOI_GIAO_HANG, A.TONG_SO_KIEN, "
    sql_query = sql_query & "B.DPHIEU_HANGID, B.SO_TK, CAST(B.NGAY_DK AS DATE) AS NGAY_DK, B.DINH_DANH_HANG_HOA, B.MA_SP, B.TEN_SP, B.STTHANG, B.MA_NUOC, B.SO_LUONG, B.MA_DVT, B.TRONG_LUONG_GW, B.TRONG_LUONG_NW, "
    sql_query = sql_query & "B.DON_GIA, B.TRI_GIA AS GIA_NHAP, B.MA_HS, B.VI_TRI_HANG, B.SO_CONT, '' AS SO_SEAL, S.TEN_NGUON, T.TEN_DVT, G.TEN_KH, CAST('' AS NVARCHAR(100)) AS GHI_CHU, B.GHI_CHU AS GHI_CHU_HANG, B.SO_QUAN_LY "
    sql_query = sql_query & "FROM DPHIEU A WITH (NOLOCK) INNER JOIN DPHIEU_HANG B WITH (NOLOCK) ON A.DPHIEUID = B.DPHIEUID AND ISNULL(B.IS_HUY, 0) = 0 "
    sql_query = sql_query & "LEFT JOIN DHOPDONG F WITH (NOLOCK) ON A.DHOPDONGID = F.DHOPDONGID LEFT JOIN SKHACHHANG G WITH (NOLOCK) ON G.MA_KH = F.MA_KH AND F.MA_KNQ = G.MA_KNQ "
    sql_query = sql_query & "LEFT JOIN SNGUONHANG S WITH (NOLOCK) ON S.MA_NGUON = A.MA_NGUON LEFT JOIN SDVT T WITH (NOLOCK) ON B.MA_DVT = T.MA_DVT "
    sql_query = sql_query & "WHERE A.MA_KNQ = @MaKNQ AND A.TYPE = 2 AND A._XORN = 'N' AND A.TRANG_THAI = 'T' "
    sql_query = sql_query & "AND ((A.PB_PHIEU = 'CT' AND A.DPHIEUID_NEXT IS NULL) OR (A.PB_PHIEU = 'SU' AND A.DPHIEUID_PREV IS NOT NULL)) "
    sql_query = sql_query & "AND A.NGAY_PHIEU >= @StartDate AND A.NGAY_PHIEU <= @EndDate; " & vbCrLf

    ' STEP 4: 联动计算“仓内所有权虚拟过户”的冲抵
    sql_query = sql_query & "IF OBJECT_ID('tempdb..#DVANBAN') IS NOT NULL DROP TABLE #DVANBAN; " & vbCrLf
    sql_query = sql_query & "SELECT CAST(CAST(DHOPDONGID_GUI AS VARCHAR) + ';' + CAST(TYPE AS VARCHAR) + ';' + CAST(DINH_DANH_HANG_HOA AS VARCHAR) + ';' AS NVARCHAR(100)) AS CKEYS, "
    sql_query = sql_query & "B.DVANBANID, B.DHOPDONGID_GUI, F.SO_HD AS SO_HD_GUI, B.DHOPDONGID_NHAN, G.SO_HD AS SO_HD_NHAN, B.SOTK, A.TYPE, A.SO_PHIEU_N, A.STTHANG_N, A.MA_SP, A.DINH_DANH_HANG_HOA, A.SO_LUONG, A.TRI_GIA "
    sql_query = sql_query & "INTO #DVANBAN FROM DVANBAN_HANG A WITH (NOLOCK), DVANBAN B WITH (NOLOCK), DHOPDONG F WITH (NOLOCK), DHOPDONG G WITH (NOLOCK) "
    sql_query = sql_query & "WHERE B.MA_KNQ = @MaKNQ AND B.TRANG_THAI = '2' AND A.DVANBANID = B.DVANBANID AND B.DHOPDONGID_GUI = F.DHOPDONGID AND B.DHOPDONGID_NHAN = G.DHOPDONGID "
    sql_query = sql_query & "AND (EXISTS(SELECT 1 FROM #NHAP C WHERE B.DHOPDONGID_GUI = C.DHOPDONGID GROUP BY C.DHOPDONGID) OR EXISTS(SELECT 1 FROM #NHAP C WHERE B.DHOPDONGID_NHAN = C.DHOPDONGID GROUP BY C.DHOPDONGID)); " & vbCrLf

    sql_query = sql_query & "UPDATE #NHAP SET GHI_CHU = TEN_NGUON + N' t? HD s?: ' + SO_HD_GUI FROM #NHAP A, #DVANBAN B WHERE A.MA_NGUON = 'N4' "
    sql_query = sql_query & "AND A.TYPE = B.TYPE AND A.DHOPDONGID = B.DHOPDONGID_NHAN AND A.DINH_DANH_HANG_HOA = B.DINH_DANH_HANG_HOA AND A.MA_SP = B.MA_SP AND A.SO_LUONG = B.SO_LUONG; " & vbCrLf

    sql_query = sql_query & "IF OBJECT_ID('tempdb..#NHAP2') IS NOT NULL DROP TABLE #NHAP2; " & vbCrLf
    sql_query = sql_query & "IF OBJECT_ID('tempdb..#DVANBAN2') IS NOT NULL DROP TABLE #DVANBAN2; " & vbCrLf

    sql_query = sql_query & "SELECT ROW_NUMBER() OVER(PARTITION BY CKEYS ORDER BY NGAY_PHIEU, DPHIEUID, DPHIEU_HANGID) AS STT, *, SO_LUONG AS SO_LUONG2, TRI_GIA AS TRI_GIA2, 0*SO_LUONG AS SO_LUONG_SD, TRI_GIA AS TRI_GIA_SD INTO #NHAP2 FROM #NHAP; " & vbCrLf
    sql_query = sql_query & "SELECT CKEYS, SUM(SO_LUONG) AS SO_LUONG, 0*SUM(SO_LUONG) AS SO_LUONG_SD, SUM(SO_LUONG) AS SO_LUONG_TON, SUM(TRI_GIA) TRI_GIA, 0*SUM(TRI_GIA) AS TRI_GIA_SD, SUM(TRI_GIA) AS TRI_GIA_TON INTO #DVANBAN2 FROM #DVANBAN A GROUP BY CKEYS; " & vbCrLf
    sql_query = sql_query & "DROP TABLE #NHAP, #DVANBAN; " & vbCrLf

    ' 核心 WHILE 循环：分摊扣减
    sql_query = sql_query & "DECLARE @i INT = 1, @j INT = ISNULL((SELECT MAX(STT) FROM #NHAP2), 1); " & vbCrLf
    sql_query = sql_query & "WHILE (@i <= @j) BEGIN " & vbCrLf
    sql_query = sql_query & "  UPDATE #NHAP2 SET SO_LUONG_SD = CASE WHEN B.SO_LUONG_TON > A.SO_LUONG THEN A.SO_LUONG ELSE B.SO_LUONG_TON END, TRI_GIA_SD = CASE WHEN B.TRI_GIA_TON > A.TRI_GIA THEN A.TRI_GIA ELSE B.TRI_GIA_TON END FROM #NHAP2 A, #DVANBAN2 B WHERE A.CKEYS = B.CKEYS AND B.SO_LUONG_TON > 0 AND STT = @i; " & vbCrLf
    sql_query = sql_query & "  UPDATE #DVANBAN2 SET SO_LUONG_SD = B.SO_LUONG_SD, TRI_GIA_SD = B.TRI_GIA_SD FROM #DVANBAN2 A, (SELECT CKEYS, SUM(SO_LUONG_SD) SO_LUONG_SD, SUM(TRI_GIA_SD) TRI_GIA_SD FROM #NHAP2 WHERE SO_LUONG_SD > 0 GROUP BY CKEYS) B WHERE A.CKEYS = B.CKEYS; " & vbCrLf
    sql_query = sql_query & "  UPDATE #DVANBAN2 SET SO_LUONG_TON = SO_LUONG - SO_LUONG_SD, TRI_GIA_TON = TRI_GIA - TRI_GIA_SD; " & vbCrLf
    sql_query = sql_query & "  SET @i += 1; " & vbCrLf
    sql_query = sql_query & "END; " & vbCrLf

    sql_query = sql_query & "UPDATE #NHAP2 SET SO_LUONG = SO_LUONG2 - SO_LUONG_SD, TRI_GIA = TRI_GIA2 - SO_LUONG_SD * GIA_NHAP; " & vbCrLf
    sql_query = sql_query & "UPDATE #NHAP2 SET GHI_CHU = N'Xu?t chuy?n quy?n sang h?p ??ng khác : ' + CAST(SO_LUONG_SD AS VARCHAR) WHERE SO_LUONG_SD > 0; " & vbCrLf
    sql_query = sql_query & "DELETE #NHAP2 WHERE SO_LUONG = 0; " & vbCrLf
    sql_query = sql_query & "DROP TABLE #DVANBAN2; " & vbCrLf

    ' ★ STEP 5: 最终输出 (严格转化为 23列 Excel 原生表头)
    sql_query = sql_query & "SELECT ROW_NUMBER() OVER(ORDER BY NGAY_PHIEU DESC, SO_PHIEU DESC, STTHANG ASC) AS [STT], "
    sql_query = sql_query & "SO_TK AS [S? TK nh?p], NGAY_DK AS [Ngày TK], SO_HD AS [S? h?p ??ng], NGAY_HD AS [Ngày h?p ??ng], "
    sql_query = sql_query & "SO_CHUNG_TU AS [Ch?ng t? n?i b?], TEN_NGUOI_GIAO_HANG AS [Ng??i giao hàng], TONG_SO_KIEN AS [T?ng s? ki?n], "
    sql_query = sql_query & "SO_PHIEU AS [S? phi?u], NGAY_PHIEU AS [Ngày nh?p kho], MA_SP AS [M? hàng], TEN_SP AS [Tên hàng], MA_NUOC AS [Xu?t x?], "
    sql_query = sql_query & "SO_LUONG AS [L??ng], TEN_DVT AS [??n v? tính], TRONG_LUONG_GW AS [Tr?ng l??ng GW], TRONG_LUONG_NW AS [Tr?ng l??ng NW], "
    sql_query = sql_query & "TRI_GIA AS [Tr? Giá], SO_QUAN_LY AS [S? qu?n ly NB], SO_CONT AS [S? container], SO_SEAL AS [S? chì HQ], "
    sql_query = sql_query & "GHI_CHU AS [Ghi chú], GHI_CHU_HANG AS [Ghi chú hàng] "
    sql_query = sql_query & "FROM #NHAP2 ORDER BY [Ngày nh?p kho] DESC, [S? phi?u] DESC, STTHANG ASC; " & vbCrLf
    sql_query = sql_query & "DROP TABLE #NHAP2;"
    ' =========================================================================
    
    ' Create a new connection
    Set connection = CreateObject("ADODB.Connection")
    With connection
        .ConnectionString = "Provider=SQLOLEDB;Data Source=" & server_name &
                            ";Initial Catalog=" & database_name &
                            ";Integrated Security=SSPI;"
        .CommandTimeout = 0 ' 防止查询超时
        .Open
    End With
    
    ' Execute SQL query
    Set rs = CreateObject("ADODB.Recordset")
    rs.CursorLocation = 3 ' adUseClient (针对复杂的 WHILE 循环更新必填)

    ' 终极排错：如遇问题可按 Ctrl + G 在立即窗口查看
    Debug.Print sql_query

    ' 开启记录集
    rs.Open sql_query, connection

    ' ★ 穿透所有在 UPDATE 和 WHILE 循环中产生的空游标
    Do While rs.State = 0 ' adStateClosed
        Set rs = rs.NextRecordset
        If rs Is Nothing Then Exit Do
    Loop

    ' Set excel_ws to the target sheet
    On Error Resume Next
    Set excel_ws = ThisWorkbook.Sheets("KNQ_4W_Import")
    If excel_ws Is Nothing Then
        MsgBox "未找到名为 'KNQ_4W_Import' 的工作表，请新建该工作表或修改代码中的名字！", vbCritical
        GoTo Cleanup
    End If
    On Error GoTo 0

    ' Clear existing content
    excel_ws.Cells.Clear

    ' 验证 rs 状态是否正常打开
    If rs Is Nothing Or rs.State = 0 Then
        MsgBox "查询中断！未能获取到有效数据集。", vbCritical
        GoTo Cleanup
    End If

    ' Write field names (column headers)
    fieldCount = rs.Fields.Count
    For i = 0 To fieldCount - 1
        excel_ws.Cells(1, i + 1).Value = rs.Fields(i).Name
    Next i

    ' 防护：如果记录集为空，直接跳过填充步骤
    If Not rs.EOF Then
        arr = rs.GetRows

        rowCount = UBound(arr, 2) + 1   ' 实际行数
        colCount = UBound(arr, 1) + 1   ' 实际列数

        ' 矩阵转置：用于快速写入数组
        ReDim arrT(1 To rowCount, 1 To colCount)
        For i = 1 To rowCount
            For j = 1 To colCount
                arrT(i, j) = arr(j - 1, i - 1)
            Next j
        Next i

        ' Apply formatting before writing data (完美贴合入库表的列位置)
        With excel_ws
            .Columns("B").NumberFormat = "@"           ' S? TK nh?p
            .Columns("C").NumberFormat = "yyyy-mm-dd"  ' Ngày TK
            .Columns("D").NumberFormat = "@"           ' S? h?p ??ng
            .Columns("E").NumberFormat = "yyyy-mm-dd"  ' Ngày h?p ??ng
            .Columns("F").NumberFormat = "@"           ' Ch?ng t? n?i b?
            .Columns("I").NumberFormat = "@"           ' S? phi?u
            .Columns("J").NumberFormat = "yyyy-mm-dd"  ' Ngày nh?p kho
            .Columns("K").NumberFormat = "@"           ' M? hàng
            .Columns("S").NumberFormat = "@"           ' S? qu?n ly NB
            .Columns("T").NumberFormat = "@"           ' S? container
            .Columns("U").NumberFormat = "@"           ' S? chì HQ

            ' 极速批量写入
            .Range("A2").Resize(rowCount, colCount).Value = arrT
        End With

        'MsgBox "KNQ_4W_IMPORTED (精确版) 数据提取成功！共加载了 " & rowCount & " 行数据。", vbInformation
    Else
        'MsgBox "查询完成，但在所选时间段内没有符合的净留存入库数据。", vbExclamation
    End If

    ' 赋予漂亮的 UI 高亮色
    With excel_ws
        .Columns.AutoFit
        .Range("B1:E1").Interior.ColorIndex = 10
        .Range("B1:E1").Font.ColorIndex = 2
        .Range("I1:J1").Interior.ColorIndex = 5
        .Range("I1:J1").Font.ColorIndex = 2
        .Range("T1:U1").Interior.ColorIndex = 46
        .Range("T1:U1").Font.ColorIndex = 2
    End With

Cleanup:
    ' 资源回收
    If Not rs Is Nothing Then
        If rs.State = 1 Then rs.Close
    End If
    If Not connection Is Nothing Then
        If connection.State = 1 Then connection.Close
    End If
    Set rs = Nothing
    Set connection = Nothing
End Sub

