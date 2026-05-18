Sub a003_KNQ_4W_EXPORTED_SQLSERVER_()
    Application.ScreenUpdating = False
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

    ' ★ 核心修复：从单元格获取日期，增加【防弹清洗机制】，彻底过滤掉潜伏的单引号和双引号
    rawStart = Replace(Replace(Sheet25.Range("C2").Value, "'", ""), """", "")
    rawEnd = Replace(Replace(Sheet25.Range("C3").Value, "'", ""), """", "")

    ' 强制格式化为 SQL 认识的标准格式 yyyy-MM-dd
    startdate = Format(rawStart, "yyyy-MM-dd")
    enddate = Format(rawEnd, "yyyy-MM-dd")

    ' =========================================================================
    ' 构造终极完整版 KNQ_4W_EXPORTED SQL 脚本
    ' =========================================================================
    sql_query = ""
    sql_query = sql_query & "SET NOCOUNT ON; " & vbCrLf
    sql_query = sql_query & "SET ANSI_WARNINGS OFF; " & vbCrLf
    sql_query = sql_query & "SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED; " & vbCrLf

    ' ★ 严格规范的单引号包裹，确保生成的 SQL 是正确的 '2026-05-01' 格式
    sql_query = sql_query & "DECLARE @MaKNQ NVARCHAR(50) = 'VNNSL'; " & vbCrLf
    sql_query = sql_query & "DECLARE @StartDate DATETIME = '" & startdate & "'; " & vbCrLf
    sql_query = sql_query & "DECLARE @EndDate DATETIME = '" & enddate & "'; " & vbCrLf

    ' STEP 1: 提取集装箱重箱
    sql_query = sql_query & "IF OBJECT_ID('tempdb..#XUAT') IS NOT NULL DROP TABLE #XUAT; " & vbCrLf
    sql_query = sql_query & "SELECT CAST('' AS NVARCHAR(100)) AS CKEYS, A.TYPE, A.SOTK AS SOTK_X, A.NGAY_DK AS NGAY_DK_X, A.SO_PHIEU, A.NGAY_PHIEU, A.DPHIEUID, A.DHOPDONGID, A.SO_HD, A.NGAY_HD, "
    sql_query = sql_query & "MAX(A.SO_BBBG) AS SO_BBBG, MAX(A.SO_CHUNG_TU) AS SO_CHUNG_TU, MAX(A.TEN_NGUOI_NHAN_HANG) AS TEN_NGUOI_NHAN_HANG, MAX(A.TONG_SO_KIEN) AS TONG_SO_KIEN, MAX(A.PHUONG_TIEN) AS PHUONG_TIEN, "
    sql_query = sql_query & "B.SO_PHIEU_N, B.STTHANG_N, B.STTHANG, B.SO_TK, CAST(B.NGAY_DK AS DATE) AS NGAY_DK, B.MA_SP, B.DINH_DANH_HANG_HOA, B.SO_CONT, "
    sql_query = sql_query & "MAX(B.TEN_SP) AS TEN_SP, MAX(B.MA_NUOC) AS MA_NUOC, MAX(B.MA_HS) AS MA_HS, SUM(B.SO_LUONG) AS SO_LUONG, MAX(B.MA_DVT) AS MA_DVT, SUM(B.TRONG_LUONG_GW) AS TRONG_LUONG_GW, SUM(B.TRONG_LUONG_NW) AS TRONG_LUONG_NW, "
    sql_query = sql_query & "SUM(B.TRI_GIA) AS TRI_GIA, MAX(B.VI_TRI_HANG) AS VI_TRI_HANG, MAX(I.TEN_DVT) AS TEN_DVT, MAX(T.TEN_CK) AS TEN_CK, MAX(DF.SO_SEAL) AS SO_SEAL, "
    sql_query = sql_query & "CAST('' AS NVARCHAR(250)) AS GHI_CHU, MAX(B.GHI_CHU) AS GHI_CHU_HANG, CAST(NULL AS DATE) AS NGAY_NHAP, CAST(NULL AS INT) AS SO_NGAY_TON, MAX(B.SO_QUAN_LY) AS SO_QUAN_LY "
    sql_query = sql_query & "INTO #XUAT FROM DPHIEU A WITH (NOLOCK) "
    sql_query = sql_query & "INNER JOIN DPHIEU_HANG B WITH (NOLOCK) ON A.DPHIEUID = B.DPHIEUID AND ISNULL(B.IS_HUY, 0) = 0 "
    sql_query = sql_query & "INNER JOIN DCONTAINER DF WITH (NOLOCK) ON DF.DPHIEUID = A.DPHIEUID AND DF.IS_RUTHANG = 0 AND DF.TINH_TRANG = 1 AND A.DRUTHANGID IS NULL "
    sql_query = sql_query & "LEFT JOIN SDVT I WITH (NOLOCK) ON B.MA_DVT = I.MA_DVT "
    sql_query = sql_query & "LEFT JOIN SCUAKHAU T WITH (NOLOCK) ON T.MA_CK = A.MA_CK_XUAT "
    sql_query = sql_query & "WHERE A.MA_KNQ = @MaKNQ AND A.TYPE = 1 AND A._XORN = 'X' AND A.MA_NGUON <> 'X4' AND A.TRANG_THAI = 'T' "
    sql_query = sql_query & "AND ((A.PB_PHIEU = 'CT' AND A.DPHIEUID_NEXT IS NULL) OR (A.PB_PHIEU = 'SU' AND A.DPHIEUID_PREV IS NOT NULL)) "
    sql_query = sql_query & "AND A.NGAY_PHIEU >= @StartDate AND A.NGAY_PHIEU <= @EndDate "
    sql_query = sql_query & "GROUP BY A.TYPE, A.SOTK, A.NGAY_DK, A.SO_PHIEU, A.NGAY_PHIEU, A.DPHIEUID, A.DHOPDONGID, A.SO_HD, A.NGAY_HD, B.SO_PHIEU_N, B.STTHANG_N, B.STTHANG, B.SO_TK, CAST(B.NGAY_DK AS DATE), B.MA_SP, B.DINH_DANH_HANG_HOA, B.SO_CONT; " & vbCrLf

    ' STEP 2: 追加散货出库
    sql_query = sql_query & "INSERT INTO #XUAT SELECT CAST('' AS NVARCHAR(100)) AS CKEYS, A.TYPE, A.SOTK AS SOTK_X, A.NGAY_DK AS NGAY_DK_X, A.SO_PHIEU, A.NGAY_PHIEU, A.DPHIEUID, A.DHOPDONGID, A.SO_HD, A.NGAY_HD, "
    sql_query = sql_query & "MAX(A.SO_BBBG) AS SO_BBBG, MAX(A.SO_CHUNG_TU) AS SO_CHUNG_TU, MAX(A.TEN_NGUOI_NHAN_HANG) AS TEN_NGUOI_NHAN_HANG, MAX(A.TONG_SO_KIEN) AS TONG_SO_KIEN, MAX(A.PHUONG_TIEN) AS PHUONG_TIEN, "
    sql_query = sql_query & "B.SO_PHIEU_N, B.STTHANG_N, B.STTHANG, B.SO_TK, CAST(B.NGAY_DK AS DATE) AS NGAY_DK, B.MA_SP, B.DINH_DANH_HANG_HOA, B.SO_CONT, "
    sql_query = sql_query & "MAX(B.TEN_SP) AS TEN_SP, MAX(B.MA_NUOC) AS MA_NUOC, MAX(B.MA_HS) AS MA_HS, SUM(B.SO_LUONG) AS SO_LUONG, MAX(B.MA_DVT) AS MA_DVT, "
    sql_query = sql_query & "SUM(B.TRONG_LUONG_GW) AS TRONG_LUONG_GW, SUM(B.TRONG_LUONG_NW) AS TRONG_LUONG_NW, SUM(B.TRI_GIA) AS TRI_GIA, MAX(B.VI_TRI_HANG) AS VI_TRI_HANG, "
    sql_query = sql_query & "MAX(I.TEN_DVT) AS TEN_DVT, MAX(T.TEN_CK) AS TEN_CK, '' AS SO_SEAL, '' AS GHI_CHU, MAX(B.GHI_CHU) AS GHI_CHU_HANG, CAST(NULL AS DATE) AS NGAY_NHAP, CAST(NULL AS INT) AS SO_NGAY_TON, MAX(B.SO_QUAN_LY) AS SO_QUAN_LY "
    sql_query = sql_query & "FROM DPHIEU A WITH (NOLOCK) INNER JOIN DPHIEU_HANG B WITH (NOLOCK) ON (A.DPHIEUID = B.DPHIEUID AND ISNULL(B.IS_HUY, 0) = 0) "
    sql_query = sql_query & "LEFT JOIN SDVT I WITH (NOLOCK) ON B.MA_DVT = I.MA_DVT LEFT JOIN SCUAKHAU T WITH (NOLOCK) ON T.MA_CK = A.MA_CK_XUAT "
    sql_query = sql_query & "WHERE A.MA_KNQ = @MaKNQ AND A.TYPE = 2 AND A._XORN = 'X' AND A.MA_NGUON <> 'X4' AND A.TRANG_THAI = 'T' "
    sql_query = sql_query & "AND ((A.PB_PHIEU = 'CT' AND A.DPHIEUID_NEXT IS NULL) OR (A.PB_PHIEU = 'SU' AND A.DPHIEUID_PREV IS NOT NULL)) "
    sql_query = sql_query & "AND A.NGAY_PHIEU >= @StartDate AND A.NGAY_PHIEU <= @EndDate "
    sql_query = sql_query & "GROUP BY A.TYPE, A.SOTK, A.NGAY_DK, A.SO_PHIEU, A.NGAY_PHIEU, A.DPHIEUID, A.DHOPDONGID, A.SO_HD, A.NGAY_HD, B.SO_PHIEU_N, B.STTHANG_N, B.STTHANG, B.SO_TK, CAST(B.NGAY_DK AS DATE), B.MA_SP, B.DINH_DANH_HANG_HOA, B.SO_CONT; " & vbCrLf

    ' STEP 3: 引入海关销毁单平账
    sql_query = sql_query & "INSERT INTO #XUAT SELECT CAST('' AS NVARCHAR(100)) AS CKEYS, 2 AS TYPE, '' AS SOTK_X, NULL AS NGAY_DK_X, B.SO_PHIEU, B.NGAY_PHIEU, 0 AS DPHIEUID, A.DHOPDONGID, A.SO_HD, H.NGAY_NHAP AS NGAY_HD, E.SO_BBBG, '' AS SO_CHUNG_TU, '' AS TEN_NGUOI_NHAN_HANG, A.SO_KIEN, E.PHUONG_TIEN, A.SO_PHIEU_N, E.STTHANG_N, NULL AS STTHANG, E.SO_TK, CAST(E.NGAY_DK AS DATE) AS NGAY_DK, A.MA_SP, A.DINH_DANH_HANG_HOA, E.SO_CONT, A.TEN_SP, E.MA_NUOC, E.MA_HS, A.SO_LUONG, A.MA_DVT, E.TRONG_LUONG_GW, E.TRONG_LUONG_NW, E.TRI_GIA, E.VI_TRI_HANG, I.TEN_DVT, T.TEN_CK, '' AS SO_SEAL, CAST(N'Hàng tiêu h?y' AS NVARCHAR(250)) AS GHI_CHU, A.GHI_CHU AS GHI_CHU_HANG, E.NGAY_PHIEU AS NGAY_NHAP, CAST(NULL AS INT) AS SO_NGAY_TON, '' AS SO_QUAN_LY "
    sql_query = sql_query & "FROM DTIEUHUY_CT A WITH (NOLOCK) INNER JOIN DTIEUHUY B WITH (NOLOCK) ON A.DTIEUHUYID = B.DTIEUHUYID "
    sql_query = sql_query & "INNER JOIN (SELECT D.DHOPDONGID, D.SO_PHIEU, D.NGAY_PHIEU, D.SO_BBBG, D.PHUONG_TIEN, D.MA_CK_XUAT, D.MA_NGUON, C.STTHANG_N, C.DINH_DANH_HANG_HOA, C.SO_TK, CAST(C.NGAY_DK AS DATE) AS NGAY_DK, C.SO_CONT, C.MA_NUOC, C.MA_HS, C.TRONG_LUONG_NW, C.TRONG_LUONG_GW, C.TRI_GIA, C.VI_TRI_HANG FROM DPHIEU_HANG C INNER JOIN DPHIEU D ON C.DPHIEUID = D.DPHIEUID AND D.MA_KNQ = @MaKNQ AND D.TYPE = 2 AND D._XORN = 'N' AND D.TRANG_THAI = 'T' AND ((D.PB_PHIEU = 'CT' AND D.DPHIEUID_NEXT IS NULL) OR (D.PB_PHIEU = 'SU' AND D.DPHIEUID_PREV IS NOT NULL))) E ON A.DHOPDONGID = E.DHOPDONGID AND A.DINH_DANH_HANG_HOA = E.DINH_DANH_HANG_HOA AND A.SO_PHIEU_N = E.SO_PHIEU "
    sql_query = sql_query & "INNER JOIN DHOPDONG H WITH (NOLOCK) ON A.DHOPDONGID = H.DHOPDONGID LEFT JOIN SDVT I WITH (NOLOCK) ON A.MA_DVT = I.MA_DVT LEFT JOIN SCUAKHAU T WITH (NOLOCK) ON T.MA_CK = E.MA_CK_XUAT "
    sql_query = sql_query & "WHERE B.MA_KNQ = @MaKNQ AND B.TRANG_THAI = '1' AND B.NGAY_PHIEU >= @StartDate AND B.NGAY_PHIEU <= @EndDate; " & vbCrLf

    ' STEP 4: 穿透溯源入库单
    sql_query = sql_query & "UPDATE X SET "
    sql_query = sql_query & "X.SO_TK = ISNULL(NULLIF(X.SO_TK, ''), PN.SO_TK), "
    sql_query = sql_query & "X.NGAY_DK = ISNULL(X.NGAY_DK, CAST(PN.NGAY_DK AS DATE)), "
    sql_query = sql_query & "X.SO_HD = ISNULL(NULLIF(X.SO_HD, ''), P.SO_HD), "
    sql_query = sql_query & "X.NGAY_HD = ISNULL(X.NGAY_HD, P.NGAY_HD), "
    sql_query = sql_query & "X.NGAY_NHAP = ISNULL(X.NGAY_NHAP, CAST(P.NGAY_PHIEU AS DATE)) "
    sql_query = sql_query & "FROM #XUAT X "
    sql_query = sql_query & "INNER JOIN DPHIEU P WITH (NOLOCK) ON X.SO_PHIEU_N = P.SO_PHIEU AND P.MA_KNQ = @MaKNQ AND P._XORN = 'N' "
    sql_query = sql_query & "INNER JOIN DPHIEU_HANG PN WITH (NOLOCK) ON P.DPHIEUID = PN.DPHIEUID AND X.DINH_DANH_HANG_HOA = PN.DINH_DANH_HANG_HOA; " & vbCrLf

    ' 算准库存账龄
    sql_query = sql_query & "UPDATE #XUAT SET SO_NGAY_TON = DATEDIFF(dd, NGAY_NHAP, NGAY_PHIEU) + 1; " & vbCrLf

    ' STEP 5: 最终输出 (完美对齐Excel表头与排序)
    sql_query = sql_query & "SELECT ROW_NUMBER() OVER(ORDER BY NGAY_PHIEU DESC, SO_PHIEU DESC) AS [STT], "
    sql_query = sql_query & "SO_TK AS [S? TK nh?p], NGAY_DK AS [Ngày TK], SO_HD AS [S? h?p ??ng], NGAY_HD AS [Ngày h?p ??ng], SO_PHIEU AS [S? phi?u], NGAY_PHIEU AS [Ngày phi?u], "
    sql_query = sql_query & "SO_CHUNG_TU AS [Ch?ng t? n?i b?], TONG_SO_KIEN AS [T?ng s? ki?n], TEN_NGUOI_NHAN_HANG AS [Ng??i nh?n hàng], SOTK_X AS [S? t? khai/CT], NGAY_DK_X AS [Ngày t? khai], "
    sql_query = sql_query & "NGAY_PHIEU AS [Ngày xu?t kho], NGAY_NHAP AS [Ngày nh?p], SO_NGAY_TON AS [S? ngày t?n], MA_SP AS [M? hàng], TEN_SP AS [Tên hàng], MA_NUOC AS [Xu?t x?], "
    sql_query = sql_query & "SO_LUONG AS [L??ng], TEN_DVT AS [??n v? tính], TRONG_LUONG_GW AS [Tr?ng l??ng GW], TRONG_LUONG_NW AS [Tr?ng l??ng NW], TRI_GIA AS [Tr? Giá], "
    sql_query = sql_query & "SO_QUAN_LY AS [S? qu?n ly NB], SO_CONT AS [S? container], SO_SEAL AS [S? chì HQ], GHI_CHU AS [Ghi chú], GHI_CHU_HANG AS [Ghi chú hàng] "
    sql_query = sql_query & "FROM #XUAT ORDER BY [Ngày phi?u] DESC, [S? phi?u] DESC; " & vbCrLf
    sql_query = sql_query & "DROP TABLE #XUAT;"
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
    
    ' ★ 核心修复：设置 CursorLocation = 3 以便正确处理返回的游标
    rs.CursorLocation = 3 ' adUseClient

    ' ★ 排错神器：如果你还会遇到错误，请按下键盘上的 Ctrl + G (打开立即窗口) 检查打印出来的 SQL
    Debug.Print sql_query

    ' 开启记录集
    rs.Open sql_query, connection

    ' ★ 穿透所有 SQL 过程产生的空游标，直到找到真正包含最终 SELECT 数据的 Recordset
    Do While rs.State = 0 ' adStateClosed
        Set rs = rs.NextRecordset
        If rs Is Nothing Then Exit Do
    Loop
    
    ' Set excel_ws to the target sheet
    Set excel_ws = ThisWorkbook.Sheets("KNQ_4W_Export")
    
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
        ' Load data into array
        arr = rs.GetRows

        rowCount = UBound(arr, 2) + 1   ' 实际行数
        colCount = UBound(arr, 1) + 1   ' 实际列数

        ' Manually transpose: arrT(row, col) format for bulk write
        ReDim arrT(1 To rowCount, 1 To colCount)
        For i = 1 To rowCount
            For j = 1 To colCount
                arrT(i, j) = arr(j - 1, i - 1)
            Next j
        Next i

        ' Apply formatting before writing data
        With excel_ws
            ' 根据提取出来的 Excel 格式，强制设置关键列为文本格式，防止柜号/报关单号/0开头的数字丢失
            .Columns("B").NumberFormat = "@"
            .Columns("C").NumberFormat = "yyyy-mm-dd"
            .Columns("D").NumberFormat = "@"
            .Columns("E").NumberFormat = "yyyy-mm-dd"
            .Columns("F").NumberFormat = "@"
            .Columns("G").NumberFormat = "yyyy-mm-dd"
            .Columns("H").NumberFormat = "@"
            .Columns("K").NumberFormat = "@"
            .Columns("L").NumberFormat = "yyyy-mm-dd"
            .Columns("M").NumberFormat = "yyyy-mm-dd"
            .Columns("N").NumberFormat = "yyyy-mm-dd"
            .Columns("P").NumberFormat = "@"
            .Columns("X").NumberFormat = "@"
            .Columns("Y").NumberFormat = "@"
            .Columns("Z").NumberFormat = "@"

            ' Bulk write array to sheet in one operation
            .Range("A2").Resize(rowCount, colCount).Value = arrT
        End With

        'MsgBox "KNQ_4W_EXPORTED Data downloaded successfully! " & rowCount & " rows loaded.", vbInformation
    Else
        'MsgBox "查询完成，但在所选时间段内没有出库数据。", vbExclamation
    End If

    ' 应用你的界面样式 (无论是否有数据都执行)
    With excel_ws
        .Columns.AutoFit
        .Range("G1:H1").Interior.ColorIndex = 10
        .Range("G1:H1").Font.ColorIndex = 2
        .Range("P1").Interior.ColorIndex = 10
        .Range("P1").Font.ColorIndex = 2
        .Range("S1").Interior.ColorIndex = 10
        .Range("S1").Font.ColorIndex = 2
    End With

Cleanup:
    ' Close recordset and connection
    If Not rs Is Nothing Then
        If rs.State = 1 Then rs.Close
    End If
    If Not connection Is Nothing Then
        If connection.State = 1 Then connection.Close
    End If
    Set rs = Nothing
    Set connection = Nothing
    Application.ScreenUpdating = True

End Sub

