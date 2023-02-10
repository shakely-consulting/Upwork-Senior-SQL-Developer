IF object_id('spnamelike') IS NOT NULL
	DROP PROCEDURE [spnamelike];
GO

CREATE PROC spnamelike (@objname VARCHAR(776))
AS
BEGIN
	SELECT OBJECT_DEFINITION(object_id) DEFINITION
		,name
	FROM sys.objects
	WHERE name LIKE  '%' + @objname + '%'
		AND OBJECT_DEFINITION(object_id) IS NOT NULL
END
GO

IF object_id('spkeys') IS NOT NULL
	DROP PROCEDURE [spkeys];
GO

CREATE PROCEDURE spkeys (@objname NVARCHAR(776) = '')
AS
BEGIN
	DECLARE @sql NVARCHAR(max);

	SET @sql = '
	SELECT ''Create'' = ''IF NOT EXISTS (SELECT * FROM sys.objects where name = '' + QUOTENAME(obj.name, '''''''') + '')'' + CHAR(10) + ''BEGIN '' + CHAR(10) + ''ALTER TABLE '' + QUOTENAME(tab1.name) + '' ADD CONSTRAINT '' + quotename(obj.name) + '' FOREIGN KEY ('' + quotename(col1.name) + '') REFERENCES '' + quotename(tab2.name) + ''('' + quotename(col2.name) + '')'' + CHAR(10) + '' END ''
		,''Drop'' = ''IF EXISTS (SELECT * FROM sys.objects where name = '' + QUOTENAME(obj.name, '''''''') + '')'' + CHAR(10) + ''BEGIN '' + CHAR(10) + ''ALTER TABLE '' + QUOTENAME(tab1.name) + '' DROP CONSTRAINT '' + quotename(obj.name) + CHAR(10) + '' END ''';
	SET @sql += '
	FROM sys.foreign_key_columns fkc
	INNER JOIN sys.objects obj ON obj.object_id = fkc.constraint_object_id
	INNER JOIN sys.tables tab1 ON tab1.object_id = fkc.parent_object_id
	INNER JOIN sys.schemas sch ON tab1.schema_id = sch.schema_id
	INNER JOIN sys.columns col1 ON col1.column_id = parent_column_id
		AND col1.object_id = tab1.object_id
	INNER JOIN sys.tables tab2 ON tab2.object_id = fkc.referenced_object_id
	INNER JOIN sys.columns col2 ON col2.column_id = referenced_column_id
		AND col2.object_id = tab2.object_id
	WHERE 1=1 ';

	IF @objname <> ''
	BEGIN
		SET @sql += '
       AND obj.name = ' + quotename(@objname, '''') + '
		OR tab1.name = ' + quotename(@objname, '''') + '
		OR tab2.name = ' + quotename(@objname, '''') + ';'
	END

	BEGIN TRY
		EXEC sp_executesql @sql;
	END TRY

	BEGIN CATCH
		SELECT @sql;
	END CATCH
END
GO
IF object_id('spcontents') IS NOT NULL
	DROP PROCEDURE [spcontents]
GO

CREATE PROCEDURE spcontents (
	@objname SYSNAME
	,@WhereClause NVARCHAR(max) = NULL
	,@includePK INT = 0
	,@nums INT = - 1
	,@debug INT = 0
	)
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @sql2 NVARCHAR(max)
		,@ident INT
		,@top NVARCHAR(100) = ' top ';

	SET @objname = RTRIM(@objname);

	IF OBJECT_ID('tempdb..##temp') IS NOT NULL
		DROP TABLE ##temp;

	IF OBJECT_ID('tempdb..##tempdata') IS NOT NULL
		DROP TABLE ##tempdata;

	IF OBJECT_ID('tblspcontents_tempdata') IS NOT NULL
		DROP TABLE tblspcontents_tempdata;

	IF OBJECT_ID('tblspcontents_temp') IS NOT NULL
		DROP TABLE tblspcontents_temp;

	CREATE TABLE [##tempdata] (
		[HMY] NUMERIC(18, 0) IDENTITY(1, 1)
		,[ID] INT NULL
		,[TheData] NVARCHAR(max) NULL CONSTRAINT [PK_##tempdata] PRIMARY KEY NONCLUSTERED ([HMY] ASC) WITH (
			PAD_INDEX = OFF
			,STATISTICS_NORECOMPUTE = OFF
			,IGNORE_DUP_KEY = OFF
			,ALLOW_ROW_LOCKS = ON
			,ALLOW_PAGE_LOCKS = ON
			) ON [PRIMARY]
		) ON [PRIMARY];

	CREATE TABLE [##temp] (
		[HMY] NUMERIC(18, 0) IDENTITY(1, 1)
		,[ID] INT NULL
		,InsertColumn NVARCHAR(max) NULL CONSTRAINT [PK_##temp] PRIMARY KEY NONCLUSTERED ([HMY] ASC) WITH (
			PAD_INDEX = OFF
			,STATISTICS_NORECOMPUTE = OFF
			,IGNORE_DUP_KEY = OFF
			,ALLOW_ROW_LOCKS = ON
			,ALLOW_PAGE_LOCKS = ON
			) ON [PRIMARY]
		) ON [PRIMARY];

	DECLARE @objid INT = object_id(@objname)
		,@tableCreation NVARCHAR(MAX)
		,@SQL NVARCHAR(MAX)
		,@v_Where NVARCHAR(max)
		,@insertlen NUMERIC;

	SET @v_Where = ISNULL(@WhereClause, '0=0');
	SET @SQL = 'INSERT INTO ' + quotename(@objname) + ' ( ' + CHAR(10)
	SET @SQL += (
			SELECT (
					SELECT STUFF((
								SELECT ',' + quotename(c.name) + ' ' + CHAR(10)
								FROM SYS.all_columns c
								WHERE object_id = @objid
									AND c.name <> 'tRowVersion'
									AND type_name(c.user_type_id) <> 'image'
									AND type_name(c.user_type_id) <> 'varbinary'
									AND c.name NOT LIKE '%select%'
									AND type_name(c.user_type_id) NOT LIKE '%text%'
									AND (
										c.is_identity = 0
										OR c.is_identity = @includePK
										)
								FOR XML PATH('')
									,TYPE
								).value('.', 'nvarchar(MAX)'), 1, 1, '')
					) + ')'
			)
	SET @insertlen = LEN('SELECT ')
	SET @SQL += 'SELECT ';

	INSERT INTO ##temp (
		ID
		,InsertColumn
		)
	SELECT 1 ID
		,@SQL AS InsertColumn;

	IF @debug = 1
		SELECT *
		INTO tblspcontents_temp
		FROM ##temp;

	IF @WhereClause IS NULL
		SET @WhereClause = ' 0=0 ';

	SELECT @SQL = '';

	SELECT @SQL += 'INSERT INTO ##tempdata (ID, TheData) SELECT 1 AS ID,' + STUFF((
				SELECT '+ ' + QUOTENAME(',', '''') + CASE
						WHEN type_name(c.user_type_id) LIKE '%date%'
							THEN '+ CASE WHEN ISNULL(RTRIM(REPLACE(' + quotename(object_name(object_id)) + '.' + quotename(c.name) + ',' + '''''''''' + ',' + '''' + '0' + '''' + ')' + '), ' + '''' + 'NULL' + '''' + ') = ''NULL'' THEN ''NULL'' ELSE ' + '''' + '''' + '''' + '''+' + ' REPLACE(RTRIM(' + quotename(object_name(object_id)) + '.' + quotename(c.name) + ')' + + ',' + '''''''''' + ',' + '''''''''' + '''' + '''' + ')' + '+''' + '''' + '''' + '''' + ' END + ' + '''' + ' ' + ''''
						WHEN type_name(c.user_type_id) IN (
								'varbinary'
								,'text'
								)
							THEN '+' + '''' + '''' + '''' + '''' + 'CONVERT(VARCHAR, DecryptByKey(' + quotename(object_name(object_id)) + '.' + quotename(c.name) + ')' + ') +' + '''' + '''' + '''' + ''''
						WHEN type_name(c.user_type_id) IN (
								'int'
								,'numeric'
								,'float'
								,'tinyint'
								,'bit'
								,'smallint'
								,'decimal'
								)
							THEN '+' + '''' + '''' + '''' + '''' + '+ convert(varchar(20), ISNULL(' + quotename(object_name(object_id)) + '.' + quotename(c.name) + ',' + '''' + '0' + '''' + ')) + ' + '''' + '''' + '''' + '' + ''''
						ELSE '+ CASE WHEN ISNULL(RTRIM(REPLACE(' + quotename(object_name(object_id)) + '.' + quotename(c.name) + ',' + '''''''''' + ',' + '''' + '0' + '''' + ')' + '), ' + '''' + 'NULL' + '''' + ') = ''NULL'' THEN ''NULL'' ELSE ' + '''' + '''' + '''' + '''+' + ' REPLACE(RTRIM(' + quotename(object_name(object_id)) + '.' + quotename(c.name) + ')' + + ',' + '''''''''' + ',' + '''''''''' + '''' + '''' + ')' + '+''' + '''' + '''' + '''' + ' END + ' + '''' + ' ' + ''''
						END + ' + CHAR(10)'
				FROM SYS.all_columns c
				WHERE object_id = @objid
					AND c.name <> 'tRowVersion'
					AND type_name(c.user_type_id) <> 'image'
					AND type_name(c.user_type_id) <> 'varbinary'
					AND c.name NOT LIKE '%select%'
					AND type_name(c.user_type_id) NOT LIKE '%text%'
					AND (
						c.is_identity = 0
						OR c.is_identity = @includePK
						)
				FOR XML PATH('')
					,TYPE
				).value('.', 'nvarchar(MAX)'), 1, @insertlen, '') + ' AS ''TheData'' FROM ' + quotename(RTRIM(@objname)) + ' WITH(NOLOCK) WHERE 1=1 and ' + @v_Where;

	IF @debug = 1
		SELECT @SQL;

	SET @top = @top + convert(VARCHAR(50), @nums);

	IF @nums = - 1
		SET @top = ' ';

	BEGIN TRY
		EXEC SP_EXECUTESQL @sql;

		SET @sql2 = ' select ' + @top + ' sch.InsertColumn + '' '' + JS.TheData as [InsertStatement] from ##tempdata JS outer apply ( select InsertColumn from ##temp ) sch '

		IF @debug = 1
			SELECT @sql2;

		EXEC SP_EXECUTESQL @sql2
	END TRY

	BEGIN CATCH
		SELECT 'Error' = 'Errors below ' + convert(VARCHAR, error_line()) + ' ' + ERROR_MESSAGE()

		UNION ALL

		SELECT 'Error' = @sql

		PRINT @sql
	END CATCH

	BEGIN TRY
		IF @debug = 1
		BEGIN
			SELECT *
			INTO tblspcontents_tempdata
			FROM ##tempdata;

			SELECT @sql2;
		END
	END TRY

	BEGIN CATCH
		SELECT 'Error' = 'Please see Messages for Errors.'
			,'line' = NULL

		UNION ALL

		SELECT ERROR_MESSAGE() message
			,ERROR_LINE() line

		UNION ALL

		SELECT 'Error' = @sql2
			,NULL
	END CATCH
END;
GO

IF object_id('spgetinsert') IS NOT NULL
	DROP PROCEDURE spgetinsert;
GO

CREATE PROCEDURE spgetinsert (
	@objname SYSNAME
	,@WhereClause NVARCHAR(max) = NULL
	,@includePK BIT = 0
	,@nums INT = 1000
	,@debug INT = 0
	)
AS /* if object_id('spcontents', 'P') is not null  drop proc spcontents GO */
BEGIN
	SET NOCOUNT ON;

	DECLARE @sql2 NVARCHAR(max)
		,@ident INT;

	SET @objname = RTRIM(@objname);

	DECLARE @objid INT = object_id(@objname)
		,@tableCreation NVARCHAR(MAX)
		,@SQL NVARCHAR(MAX)
		,@v_Where NVARCHAR(max)
		,@insertlen NUMERIC
		,@COLS NVARCHAR(MAX);

	SET @v_Where = ISNULL(@WhereClause, '0=0');
	SET @COLS = (
			SELECT (
					SELECT STUFF((
								SELECT ',' + quotename(c.name) + CHAR(10)
								FROM SYS.all_columns c
								WHERE object_id = @objid
									AND c.name <> 'tRowVersion'
									AND type_name(c.user_type_id) <> 'image'
									AND type_name(c.user_type_id) <> 'varbinary'
									AND type_name(c.user_type_id) NOT LIKE '%text%'
									AND (
										c.is_identity = 0
										OR c.is_identity = @includePK
										)
								FOR XML PATH('')
									,TYPE
								).value('.', 'nvarchar(MAX)'), 1, 1, '')
					)
			)
	SET @SQL = 'INSERT INTO ' + quotename(@objname) + ' (' + CHAR(10) + @COLS + ')'
	SET @SQL += CHAR(10) + 'SELECT ' + @COLS + ' FROM ' + quotename(@objname)

	SELECT @SQL;
END
GO

IF object_id('spgetsp') IS NOT NULL
	DROP PROCEDURE [spgetsp];
GO

CREATE PROCEDURE spgetsp (@objName SYSNAME)
AS
BEGIN
	DECLARE @s NVARCHAR(max) = ''
		,@temp NVARCHAR(10) = '';
	DECLARE @sysobj_type CHAR(20);

	SET @objName = replace(replace(@objName, '[', ''), ']', '');

	SELECT @sysobj_type = CASE
			WHEN type = 'P'
				THEN 'procedure'
			WHEN type IN (
					'FN'
					,'IF'
					,'TF'
					)
				THEN 'function'
			WHEN type = 'V'
				THEN 'view'
			WHEN type = 'TR'
				THEN 'trigger'
			END
	FROM sys.all_objects
	WHERE object_id = object_id(@objname);

	IF LEFT(@objName, 1) = '#'
		SET @temp = 'tempdb..';
	SET @s += 'if object_id(''' + @temp + @objname + ''') is not null ' + char(10) + 'drop ' + RTRIM(LTRIM(@sysobj_type)) + ' ' + quotename(@objname) + CHAR(10) + 'GO' + CHAR(10);

	SET @s += REPLACE(object_definition(object_id(@objName)), 'CREATE   ', 'CREATE ')

	SELECT 'Create' = @s + CHAR(10) + 'GO' + CHAR(10);
END
GO

IF object_id('fnHasIdentity') IS NOT NULL
	DROP FUNCTION [fnHasIdentity];
GO

CREATE FUNCTION fnHasIdentity (@objname NVARCHAR(776))
RETURNS INT
AS
BEGIN
	DECLARE @dbname SYSNAME
		,@no VARCHAR(35)
		,@yes VARCHAR(35)
		,@none VARCHAR(35)
	DECLARE @colname SYSNAME
		,@IsIdentity INT

	SELECT @no = 'no'
		,@yes = 'yes'
		,@none = 'none'

	SELECT @dbname = parsename(@objname, 3)

	IF @dbname IS NULL
		SELECT @dbname = db_name()
	ELSE IF @dbname <> db_name()
	BEGIN
		RETURN 0
	END

	DECLARE @objid INT
	DECLARE @sysobj_type CHAR(2)

	SELECT @objid = object_id
		,@sysobj_type = type
	FROM sys.all_objects
	WHERE object_id = object_id(@objname)

	IF @sysobj_type IN (
			'S '
			,'U '
			,'V '
			,'TF'
			)
	BEGIN
		SELECT @colname = col_name(@objid, column_id)
		FROM sys.identity_columns
		WHERE object_id = @objid

		SELECT @IsIdentity = CASE isnull(@colname, 'NONE')
				WHEN 'NONE'
					THEN 0
				ELSE 1
				END
	END

	RETURN ISNULL(@IsIdentity, 0)
END
GO

IF object_id('SPCREATETABLE') IS NOT NULL
	DROP PROCEDURE [SPCREATETABLE]
GO

CREATE PROCEDURE spcreatetable (@objname SYSNAME)
AS
BEGIN
	DECLARE @objid INT = OBJECT_ID(@objname)
		,@tableCreation NVARCHAR(MAX)
		,@dropDummy NVARCHAR(MAX)
		,@HasIdentity NVARCHAR(max)
		,@identitycol SYSNAME
		,@boolIdentity INT
		,@end NVARCHAR(max)
		,@query NVARCHAR(MAX)

	SELECT @boolIdentity = dbo.fnHasIdentity(@objname);

	SELECT @identitycol = name
	FROM sys.all_columns
	WHERE object_name(object_id) = @objname
		AND is_identity = 1;

	SELECT @HasIdentity = '(' + CHAR(9) + CHAR(10) + CHAR(13) + CHAR(9) + QUOTENAME(@identitycol) + ' BIGINT IDENTITY (1,1) '
	FROM sys.all_columns
	WHERE is_identity = 1;

	IF @boolIdentity = 0
		SELECT @tableCreation = 'IF OBJECT_ID(' + QUOTENAME(@objname, '''') + ') IS NULL CREATE TABLE ' + QUOTENAME(@objname) + ' (';
	ELSE IF @boolIdentity = 1
		SELECT @tableCreation = 'IF OBJECT_ID(' + QUOTENAME(@objname, '''') + ') IS NULL CREATE TABLE ' + QUOTENAME(@objname) + ' ' + @HasIdentity;

	IF @boolIdentity = 0
		SELECT @end = ' ) ON [PRIMARY] ;'
	ELSE IF @boolIdentity = 1
		SELECT @end = 'CONSTRAINT ' + QUOTENAME('PK_' + @objname) + ' PRIMARY KEY NONCLUSTERED( ' + QUOTENAME(isnull(@identitycol, 'Id')) + ' ASC)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ' + 'ON [PRIMARY]) ON [PRIMARY] ' + CHAR(10);

	SELECT [Create] AS 'Create'
	FROM (
		SELECT @tableCreation AS 'Create'

		UNION ALL

		SELECT CASE
				WHEN ODB = 1
					AND @boolIdentity = 0
					THEN Col
				ELSE ', ' + Col
				END + ' NULL ' AS 'Create'
		FROM (
			SELECT ROW_NUMBER() OVER (
					ORDER BY column_id
					) AS ODB
				,(
					CASE
						WHEN type_name(user_type_id) IN (
								'numeric'
								,'decimal'
								)
							THEN QUOTENAME(name) + ' ' + type_name(user_type_id) + ' (' + convert(VARCHAR, precision) + ',' + convert(VARCHAR, scale) + ')'
						WHEN type_name(user_type_id) LIKE '%DATE%'
							THEN QUOTENAME(name) + ' ' + type_name(user_type_id)
						WHEN type_name(user_type_id) IN (
								'varchar'
								,'nvarchar'
								,'char'
								)
							AND CONVERT(INT, max_length) <> - 1
							THEN QUOTENAME(name) + ' ' + type_name(user_type_id) + ' (' + convert(VARCHAR, CONVERT(INT, max_length / CASE
											WHEN left(type_name(user_type_id), 1) = 'n'
												THEN 2
											ELSE 1
											END)) + ')'
						WHEN type_name(user_type_id) IN (
								'varchar'
								,'nvarchar'
								,'char'
								)
							AND CONVERT(INT, max_length) = - 1
							THEN QUOTENAME(name) + ' ' + type_name(user_type_id) + ' (MAX)'
						WHEN type_name(user_type_id) IN (
								'varbinary'
								,'float'
								,'text'
								)
							THEN QUOTENAME(name) + ' ' + type_name(user_type_id)
						WHEN type_name(user_type_id) IN (
								'smallint'
								,'tinyint'
								,'int'
								,'bigint'
								,'bit'
								,'money'
								,'timestamp'
								)
							THEN QUOTENAME(name) + ' ' + type_name(user_type_id)
						ELSE QUOTENAME(name) + ' ' + type_name(user_type_id)
						END
					) AS Col
			FROM sys.all_columns
			WHERE object_name(object_id) = @objname
				AND is_identity <> 1
			) AS TEMP
		WHERE Col IS NOT NULL

		UNION ALL

		SELECT @end
		) X;
END
GO


IF object_id('sp_gettableschema') IS NOT NULL
	DROP PROCEDURE [sp_gettableschema];
GO

CREATE PROCEDURE sp_gettableschema (@objname NVARCHAR(756))
AS
BEGIN
	DECLARE @objid INT = OBJECT_ID(@objname)
	DECLARE @tableCreation NVARCHAR(MAX)
	DECLARE @dropDummy NVARCHAR(MAX)
	DECLARE @HasIdentity NVARCHAR(max)
	DECLARE @precision NVARCHAR(10);
	DECLARE @identExist INT;

	SELECT @identExist = count(*)
	FROM SYS.identity_columns
	WHERE object_id = @objid;

	PRINT @identExist;

	IF @identExist > 0
	BEGIN
		SELECT @HasIdentity = '(' + quotename(name) + ' NUMERIC(' + isnull(CONVERT(VARCHAR, precision), '21') + ',' + isnull(convert(VARCHAR, scale), '0') + ')' + 'IDENTITY ' + '(' + isnull(CAST(SEED_VALUE AS VARCHAR), '1') + ',' + isnull(CAST(INCREMENT_VALUE AS VARCHAR), '1') + ')' + ' 	 CONSTRAINT ' + QUOTENAME('PK_' + @objname) + ' PRIMARY KEY NONCLUSTERED 	( [HMY] ASC )WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ' + 'ON [PRIMARY]) ON [PRIMARY] '
		FROM SYS.identity_columns
		WHERE object_id = @objid;
	END
	ELSE
	BEGIN
		SELECT @HasIdentity = ' ([HMY] NUMERIC(18,0)IDENTITY (1,1) 	 CONSTRAINT [PK_' + @objname + ']' + ' PRIMARY KEY NONCLUSTERED ( [HMY] ASC )WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ' + 'ON [PRIMARY]) ON [PRIMARY] '
	END

	SELECT @tableCreation = 'IF NOT EXISTS (SELECT 1 FROM sys.tables where NAME = ' + QUOTENAME(@objname, '''') + ') 	BEGIN  CREATE TABLE ' + QUOTENAME(@objname) + ' ' + @HasIdentity + '  END ;' + CHAR(10) + CHAR(13)

	SELECT *
	FROM (
		SELECT @tableCreation AS Query

		UNION ALL

		SELECT ' IF NOT EXISTS (select 1 from INFORMATION_SCHEMA.COLUMNS where TABLE_NAME = ' + QUOTENAME(TABLE_NAME, '''') + ' and column_name = ' + QUOTENAME(COLUMN_NAME, '''') + ') 		AND EXISTS (SELECT 1 FROM SYS.TABLES ST WHERE ST.NAME = ' + QUOTENAME(TABLE_NAME, '''') + ' ) BEGIN ' + 'ALTER TABLE ' + QUOTENAME(TABLE_NAME) + ' ADD ' + Col + ' NULL ' + ' END;' + CHAR(10) + CHAR(13) AS Query
		FROM (
			SELECT ROW_NUMBER() OVER (
					ORDER BY ORDINAL_POSITION
					) AS ODB
				,(
					CASE
						WHEN DATA_TYPE IN (
								'numeric'
								,'decimal'
								)
							THEN column_name + ' ' + DATA_TYPE + ' (' + convert(VARCHAR, numeric_precision) + ',' + convert(VARCHAR, numeric_scale) + ')'
						WHEN data_type IN (
								'datetime'
								,'date'
								,'datetime2'
								)
							THEN QUOTENAME(column_name) + ' ' + DATA_TYPE
						WHEN DATA_TYPE IN (
								'varchar'
								,'nvarchar'
								,'char'
								)
							AND CHARACTER_MAXIMUM_LENGTH <> - 1
							THEN QUOTENAME(column_name) + ' ' + DATA_TYPE + ' (' + convert(VARCHAR, CHARACTER_MAXIMUM_LENGTH) + ')'
						WHEN DATA_TYPE IN (
								'varchar'
								,'nvarchar'
								,'char'
								)
							AND CHARACTER_MAXIMUM_LENGTH = - 1
							THEN QUOTENAME(column_name) + ' ' + DATA_TYPE + ' (MAX)'
						WHEN data_type IN (
								'varbinary'
								,'text'
								)
							THEN QUOTENAME(column_name) + ' ' + DATA_TYPE
						WHEN data_type IN (
								'smallint'
								,'tinyint'
								,'int'
								,'bigint'
								,'bit'
								,'money'
								,'timestamp'
								)
							THEN QUOTENAME(column_name) + ' ' + DATA_TYPE
						ELSE QUOTENAME(column_name) + ' ' + DATA_TYPE + ' (' + ISNULL(convert(VARCHAR, CHARACTER_MAXIMUM_LENGTH), 'MAX') + ')'
						END
					) AS Col
				,TABLE_NAME
				,DATA_TYPE
				,IS_NULLABLE
				,column_name
			FROM INFORMATION_SCHEMA.COLUMNS
			WHERE TABLE_NAME = @objname
			) AS TEMP
		WHERE Col IS NOT NULL
		) X
END
GO


IF object_id('uspGetPricesRecord') IS NOT NULL
	DROP PROC [uspGetPricesRecord];
GO

CREATE PROC uspGetPricesRecord (
	@top NVARCHAR(20) = NULL
	,@symbol VARCHAR(10) = ''
	,@holdings VARCHAR(20) = '0.00628000'
	,@debug INT = 0
	)
AS
BEGIN
	SET NOCOUNT ON

	/*EXEC uspRefreshPricesRecordTable;*/
	DECLARE @s NVARCHAR(max);

	SET @s = '
;with cte
as (
	select pr.[Id]
		,row_number() over (
			partition by pr.[Open]
			,pr.[High]
			,pr.[Low]
			,pr.[Close]
			,pr.[AdjustedClose] order by [Date] desc
			) [rownum]
		,pr.UserId
		,pr.[Symbol]
		,pr.[Date]
		,pr.CreatedAt
		,pr.[Open]
		,pr.[High]
		,pr.[Low]
		,pr.[Close]
		,pr.[AdjustedClose]
		,pr.[Volume]
		,pr.[Pct_Change]
	from PricesRecords pr
	where 1 = 1
	)
select ';

	IF (
			isnull(@top, '') <> ''
			AND NOT @top = - 1
			)
		SET @s += ' TOP ' + @top + ' ';
	SET @s += '
	ROW_NUMBER() OVER (
		ORDER BY [Date] DESC, [Id] DESC
		) AS Id
	,UserId
	,cte.[Symbol]
	,cte.[Date]
	,ISNULL(cte.CreatedAt, GETUTCDATE()) CreatedAt
	,cte.[Open]
	,cte.[High]
	,cte.[Low]
	,cte.[Close]
	,cte.[AdjustedClose]
	,cte.[Volume]
	,CONVERT(DECIMAL(10, 2), CASE
			WHEN cast(CreatedAt AS DATE) = cast([Date] AS DATE)
				THEN COALESCE(cte.Pct_Change, ((AdjustedClose - cte.[Open]) / cast(cte.[Open] AS FLOAT)) * 100)
			ELSE ((AdjustedClose - cte.[Open]) / cast(cte.[Open] AS FLOAT)) * 100
			END) Pct_Change
	,[AdjustedClose] * case
		when Symbol = ';
	SET @s += ' ''JNJ'' ';
	SET @s += '  then ''1.215'' ELSE ';
	SET @s += '''' + @holdings + ''''
	SET @s += ' end as CurrentHoldings ';
	SET @s += '
from cte
where rownum = 1
order by Id , [Date] , CreatedAt  '

	IF @debug = 1
		SELECT @s;

	EXEC sp_executesql @s;
END
GO

IF object_id('sp_dumptoCSV_EtlFormat') IS NOT NULL
	DROP PROC [sp_dumptoCSV_EtlFormat];
GO

CREATE
	OR

ALTER PROCEDURE sp_dumptoCSV_EtlFormat (
	@objname VARCHAR(756) = ''
	,@debug INT = 0
	,@rowonefileheader CHAR(1) = 'Y'
	,@HeaderName VARCHAR(256) = 'PropertyNames'
	)
AS
BEGIN
	DECLARE @q NVARCHAR(max)
		,@h NVARCHAR(max)
		,@sql2 NVARCHAR(max)
		,@header NVARCHAR(MAX) = ''
		,@orderby NVARCHAR(MAX) = '';

	IF @rowonefileheader = 'Y'
		SET @header = STUFF((
					SELECT ',' + '''' + CASE
							WHEN ROW_NUMBER() OVER (
									ORDER BY column_id
									) = 1
								THEN @HeaderName
							ELSE ''
							END + '''' + ' as ' + QUOTENAME(name)
					FROM sys.all_columns
					WHERE object_name(object_id) = @objname
					ORDER BY column_id
					FOR XML PATH('')
						,TYPE
					).value('.', 'NVARCHAR(MAX)'), 1, 1, '')

	SELECT @h = STUFF((
				SELECT ',' + '''' + name + '''' + ' as ' + QUOTENAME(name)
				FROM sys.all_columns
				WHERE object_name(object_id) = @objname
				ORDER BY column_id
				FOR XML PATH('')
					,TYPE
				).value('.', 'NVARCHAR(MAX)'), 1, 1, '')

	SELECT @q = STUFF((
				SELECT ',' + '''' + '"' + '''' + '+ REPLACE(ISNULL(RTRIM(' + CASE
						WHEN type_name(user_type_id) LIKE '%DATE%'
							THEN 'FORMAT(' + QUOTENAME(NAME) + ',''MM/dd/yyyy hh:mm:ss tt''' + ')'
						ELSE QUOTENAME(NAME)
						END + '),' + '''' + '''' + '),' + '''' + '"' + '''' + ',' + '''' + '"' + '"' + '''' + ')' + '+' + '''' + '"' + '''' + CHAR(10)
				FROM sys.all_columns
				WHERE object_name(object_id) = @objname
				ORDER BY column_id
				FOR XML PATH('')
					,TYPE
				).value('.', 'NVARCHAR(MAX)'), 1, 1, '') + ' ' + CHAR(10);

	SELECT @q = 'SELECT ' + SUBSTRING(@q, 1, LEN(@q) - 0) + CHAR(10) + ' from ' + @objname + CHAR(10);

	SET @sql2 = 'SELECT * FROM (SELECT ' + @header + CHAR(10) + 'UNION ALL' + CHAR(10) + 'SELECT ' + @h + CHAR(10) + ' union ALL ' + CHAR(10) + @q + CHAR(10) + ' ) X ' + @orderby + CHAR(10);

	IF (@debug = 1)
	BEGIN
		SELECT @sql2
	END

	EXEC SP_EXECUTESQL @sql2;
END
GO

DECLARE @mysql NVARCHAR(MAX);

SET @mysql = '
IF object_id(''trg_syspermissions'') IS NOT NULL
	DROP TRIGGER [trg_syspermissions];';

EXEC SP_EXECUTESQL @mysql;

SET @mysql  = '
CREATE TRIGGER trg_syspermissions ON dbo.SysPermissionExceptions
AFTER INSERT
	,UPDATE
AS
DECLARE @ihmy NUMERIC;

SELECT @ihmy = hmy
FROM inserted;

BEGIN
	SET NOCOUNT ON;

	IF
		UPDATE (huser)
			AND (
				SELECT count(*)
				FROM inserted
				WHERE hMy = @ihmy
				) > 0

	DECLARE @hgroup NUMERIC
		,@sobjname VARCHAR(100);

	SELECT @hgroup = HGROUP
	FROM PMUSER WITH (NOLOCK)
	WHERE HMY = (
			SELECT huser
			FROM inserted
			WHERE hmy = @ihmy
			);

	SELECT @sobjname = sToken
	FROM inserted
	WHERE hmy = @ihmy;

	BEGIN
		INSERT INTO iSecurity2 (
			HGROUP
			,SOBJNAME
			,IACCESS
			,IOBJTYPE
			)
		SELECT DISTINCT @hgroup
			,LTRIM(RTRIM(STOKEN))
			,2
			,0
		FROM SysPermissionExceptions WITH (NOLOCK)
		WHERE hmy = @ihmy
			AND NOT EXISTS (
				SELECT 1
				FROM isecurity2 WITH (NOLOCK)
				WHERE HGROUP = @hgroup
					AND SOBJNAME = SysPermissionExceptions.sToken
				);

		IF NOT EXISTS (
				SELECT *
				FROM SysPermissionExceptions WITH (NOLOCK)
				WHERE hmy = @ihmy
					AND NOT EXISTS (
						SELECT 1
						FROM isecurity2 WITH (NOLOCK)
						WHERE HGROUP = @hgroup
							AND SOBJNAME = SysPermissionExceptions.sToken
							AND isecurity2.iAccess <> 2
						)
				)
			UPDATE ISECURITY2
			SET IACCESS = 2
			WHERE HGROUP = @hgroup
				AND SOBJNAME = @sobjname
	END
END; ';


IF EXISTS (SELECT 1 FROM SYS.TABLES WHERE NAME = 'SysPermissionExceptions')
EXEC sp_executesql @mysql;
GO

IF object_id('sp_gettableschema') IS NOT NULL
	DROP PROCEDURE [sp_gettableschema]
GO

CREATE PROCEDURE sp_gettableschema (@objname NVARCHAR(756))
AS
BEGIN
	DECLARE @objid INT = OBJECT_ID(@objname)
	DECLARE @tableCreation NVARCHAR(MAX)
	DECLARE @dropDummy NVARCHAR(MAX)
	DECLARE @HasIdentity NVARCHAR(max)
	DECLARE @precision NVARCHAR(10);
	DECLARE @identExist INT;

	SELECT @identExist = count(*)
	FROM SYS.identity_columns
	WHERE object_id = @objid;


	IF @identExist > 0
	BEGIN
		SELECT @HasIdentity = '(' + quotename(name) + ' NUMERIC(' + isnull(CONVERT(VARCHAR, precision), '21') + ',' + isnull(convert(VARCHAR, scale), '0') + ')' + 'IDENTITY ' + '(' + isnull(CAST(SEED_VALUE AS VARCHAR), '1') + ',' + isnull(CAST(INCREMENT_VALUE AS VARCHAR), '1') + ')' + ' 	 CONSTRAINT ' + QUOTENAME('PK_' + @objname) + ' PRIMARY KEY NONCLUSTERED 	(' + quotename(name) + ' ASC )WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ' + 'ON [PRIMARY]) ON [PRIMARY] '
		FROM SYS.identity_columns
		WHERE object_id = @objid;
	END
	ELSE
	BEGIN
		SELECT @HasIdentity = ' ([Id] NUMERIC(18,0)IDENTITY (1,1) 	 CONSTRAINT [PK_' + @objname + ']' + ' PRIMARY KEY NONCLUSTERED ( [Id] ASC )WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ' + 'ON [PRIMARY]) ON [PRIMARY] '
	END

	SELECT @tableCreation = 'IF NOT EXISTS (SELECT 1 FROM sys.tables where NAME = ' + QUOTENAME(@objname, '''') + ') BEGIN  CREATE TABLE ' + QUOTENAME(@objname) + ' ' + @HasIdentity + '  END ;' + CHAR(10) + CHAR(13)

	SELECT *
	FROM (
		SELECT @tableCreation AS Query

		UNION ALL

		SELECT ' IF NOT EXISTS (select 1 from INFORMATION_SCHEMA.COLUMNS where TABLE_NAME = ' + QUOTENAME(TABLE_NAME, '''') + ' and column_name = ' + QUOTENAME(COLUMN_NAME, '''') + ') AND EXISTS (SELECT 1 FROM SYS.TABLES ST WHERE ST.NAME = ' + QUOTENAME(TABLE_NAME, '''') + ' ) BEGIN ' + 'ALTER TABLE ' + QUOTENAME(TABLE_NAME) + ' ADD ' + Col + CASE WHEN IS_NULLABLE = 'NO' THEN 'NOT NULL' ELSE 'NULL' END + ' END;' + CHAR(10) + CHAR(13) AS Query
		FROM (
			SELECT ROW_NUMBER() OVER (
					ORDER BY ORDINAL_POSITION
					) AS ODB
				,(
					CASE
						WHEN DATA_TYPE IN (
								'numeric'
								,'decimal'
								)
							THEN column_name + ' ' + DATA_TYPE + ' (' + convert(VARCHAR, numeric_precision) + ',' + convert(VARCHAR, numeric_scale) + ')'
						WHEN data_type IN (
								'datetime'
								,'date'
								,'datetime2'
								)
							THEN QUOTENAME(column_name) + ' ' + DATA_TYPE
						WHEN DATA_TYPE IN (
								'varchar'
								,'nvarchar'
								,'char'
								)
							AND CHARACTER_MAXIMUM_LENGTH <> - 1
							THEN QUOTENAME(column_name) + ' ' + DATA_TYPE + ' (' + convert(VARCHAR, CHARACTER_MAXIMUM_LENGTH) + ')'
						WHEN DATA_TYPE IN (
								'varchar'
								,'nvarchar'
								,'char'
								)
							AND CHARACTER_MAXIMUM_LENGTH = - 1
							THEN QUOTENAME(column_name) + ' ' + DATA_TYPE + ' (MAX)'
						WHEN data_type IN (
								'varbinary'
								,'text'
								)
							THEN QUOTENAME(column_name) + ' ' + DATA_TYPE
						WHEN data_type IN (
								'smallint'
								,'tinyint'
								,'int'
								,'bigint'
								,'bit'
								,'money'
								,'timestamp'
								)
							THEN QUOTENAME(column_name) + ' ' + DATA_TYPE
						ELSE QUOTENAME(column_name) + ' ' + DATA_TYPE + ' (' + ISNULL(convert(VARCHAR, CHARACTER_MAXIMUM_LENGTH), 'MAX') + ')'
						END
					) AS Col
				,TABLE_NAME
				,DATA_TYPE
				,IS_NULLABLE
				,column_name
			FROM INFORMATION_SCHEMA.COLUMNS
			WHERE TABLE_NAME = @objname
			) AS TEMP
		WHERE Col IS NOT NULL
		) X
END
GO
CREATE OR ALTER FUNCTION dbo.fnRemoveSpecialChars (@str NVARCHAR(MAX))
RETURNS NVARCHAR(MAX)
AS
begin
declare @allowed VARCHAR(1000) = 'a-zA-Z0- ';
WHILE (@str COLLATE Latin1_General_BIN LIKE '%[^' + @allowed + ']%')
	SET @str = STUFF(@str, PATINDEX('%[^' + @allowed + ']%', @str COLLATE Latin1_General_BIN), 1, '');
return
  @str
 end
GO


CREATE OR ALTER PROCEDURE spcontents2 (
	@objname SYSNAME
	,@WhereClause NVARCHAR(max) = NULL
	,@includePK INT = 0
	,@nums INT = 1000
	,@debug INT = 0
	)
AS /* if object_id('spcontents', 'P') is not null  drop proc spcontents go */
BEGIN
	SET NOCOUNT ON;

	DECLARE @sql2 NVARCHAR(max)
		,@ident INT;

	IF @includePK <> 0
		SELECT @includePK;

	IF (
			@includePK <> 0
			AND @includePK <> 1
			AND @includePK IS NOT NULL
			)
	BEGIN
		--exec sys.sp_addmessage @msgnum = 60000
		--	,@severity = 16
		--	,@msgtext = N'Please enter ONLY either a 1 or 0 for the parameter @includePK.'
		--	,@lang = 'us_english';
		DECLARE @msg NVARCHAR(2048) = FORMATMESSAGE(60000, 500, N'First string', N'second string');

		THROW 60000
			,@msg
			,1;
	END

	SET @objname = RTRIM(@objname);

	IF OBJECT_ID('tempdb..##temp') IS NOT NULL
		DROP TABLE ##temp;

	IF OBJECT_ID('tempdb..##tempdata') IS NOT NULL
		DROP TABLE ##tempdata;

	IF OBJECT_ID('tblspcontents_tempdata') IS NOT NULL
		DROP TABLE tblspcontents_tempdata;

	IF OBJECT_ID('tblspcontents_temp') IS NOT NULL
		DROP TABLE tblspcontents_temp;

	CREATE TABLE [##tempdata] (
		[HMY] NUMERIC(18, 0) IDENTITY(1, 1)
		,[ID] INT NULL
		,[TheData] NVARCHAR(max) NULL CONSTRAINT [PK_##tempdata] PRIMARY KEY NONCLUSTERED ([HMY] ASC) WITH (
			PAD_INDEX = OFF
			,STATISTICS_NORECOMPUTE = OFF
			,IGNORE_DUP_KEY = OFF
			,ALLOW_ROW_LOCKS = ON
			,ALLOW_PAGE_LOCKS = ON
			) ON [PRIMARY]
		) ON [PRIMARY];

	CREATE TABLE [##temp] (
		[HMY] NUMERIC(18, 0) IDENTITY(1, 1)
		,[ID] INT NULL
		,InsertColumn NVARCHAR(max) NULL CONSTRAINT [PK_##temp] PRIMARY KEY NONCLUSTERED ([HMY] ASC) WITH (
			PAD_INDEX = OFF
			,STATISTICS_NORECOMPUTE = OFF
			,IGNORE_DUP_KEY = OFF
			,ALLOW_ROW_LOCKS = ON
			,ALLOW_PAGE_LOCKS = ON
			) ON [PRIMARY]
		) ON [PRIMARY];

	DECLARE @objid INT = object_id(@objname)
		,@tableCreation NVARCHAR(MAX)
		,@SQL NVARCHAR(MAX)
		,@v_Where NVARCHAR(max)
		,@insertlen NUMERIC;

	SET @v_Where = ISNULL(@WhereClause, '0=0');
	SET @SQL = 'INSERT INTO ' + quotename(@objname) + ' (' + CHAR(10);
	SET @SQL += (
			SELECT (
					SELECT STUFF((
								SELECT ',' + quotename(c.name) + CHAR(10)
								FROM SYS.all_columns c
								WHERE object_id = @objid
									AND c.name <> 'tRowVersion'
									AND type_name(c.user_type_id) <> 'image'
									AND type_name(c.user_type_id) <> 'varbinary'
									AND c.name NOT LIKE '%select%'
									AND type_name(c.user_type_id) NOT LIKE '%text%'
									AND (
										c.is_identity = 0
										OR c.is_identity = @includePK
										)
								FOR XML PATH('')
									,TYPE
								).value('.', 'nvarchar(MAX)'), 1, 1, '')
					) + ')'
			)
	SET @insertlen = LEN('SELECT ')
	SET @SQL += 'SELECT ';

	INSERT INTO ##temp (
		ID
		,InsertColumn
		)
	SELECT 1 ID
		,@SQL AS InsertColumn;

	IF @debug = 1
		SELECT *
		INTO tblspcontents_temp
		FROM ##temp;

	IF @WhereClause IS NULL
		SET @WhereClause = ' 0=0 ';

	SELECT @SQL = '';

	SELECT @SQL += 'INSERT INTO ##tempdata (ID, TheData) SELECT 1 AS ID,' + STUFF((
				SELECT '+ ' + QUOTENAME(',', '''') + CASE
						WHEN type_name(c.user_type_id) LIKE '%date%'
							THEN '+ CASE WHEN ISNULL(RTRIM(REPLACE(' + quotename(object_name(object_id)) + '.' + quotename(c.name) + ',' + '''''''''' + ',' + '''' + '0' + '''' + ')' + /* ")" to the right is rtim close*/ '), ' + '''' + 'NULL' + '''' + ')  = ''NULL'' THEN  ''NULL'' ELSE ' + '''' + '''' + '''' + '''+' + ' REPLACE(RTRIM(' + quotename(object_name(object_id)) + '.' + quotename(c.name) + ')' + /*start here*/ + ',' + '''''''''' + ',' + '''''''''' + '''' + '''' + ')' + '+''' + '''' + '''' + '''' + '  END + ' + '''' + ' /*' + quotename(c.name) + '*/' + ''''
						WHEN type_name(c.user_type_id) IN (
								'varbinary'
								,'text'
								)
							THEN '+' + '''' + '''' + '''' + '''' + 'CONVERT(VARCHAR, DecryptByKey(' + quotename(object_name(object_id)) + '.' + quotename(c.name) + ')' + ') +' + '''' + '''' + '''' + ''''
						WHEN type_name(c.user_type_id) IN (
								'int'
								,'numeric'
								,'float'
								,'tinyint'
								,'bit'
								,'smallint'
								,'decimal'
								)
							THEN '+' + '''' + '''' + '''' + '''' + '+ convert(varchar(20), ISNULL(' + quotename(object_name(object_id)) + '.' + quotename(c.name) + ',' + '''' + '0' + '''' + ')) + ' + '''' + '''' + '''' + '/*' + quotename(c.name) + '*/' + ''''
						ELSE '+ CASE WHEN ISNULL(RTRIM(REPLACE(' + quotename(object_name(object_id)) + '.' + quotename(c.name) + ',' + '''''''''' + ',' + '''' + '0' + '''' + ')' + /* ")" to the right is rtim close*/ '), ' + '''' + 'NULL' + '''' + ')  = ''NULL'' THEN  ''NULL'' ELSE ' + '''' + '''' + '''' + '''+' + ' REPLACE(RTRIM(' + quotename(object_name(object_id)) + '.' + quotename(c.name) + ')' + /*start here*/ + ',' + '''''''''' + ',' + '''''''''' + '''' + '''' + ')' + '+''' + '''' + '''' + '''' + '  END + ' + '''' + ' /*' + quotename(c.name) + '*/' + ''''
						END
				FROM SYS.all_columns c
				WHERE object_id = @objid
					AND c.name <> 'tRowVersion'
					AND type_name(c.user_type_id) <> 'image'
					AND type_name(c.user_type_id) <> 'varbinary'
					AND c.name NOT LIKE '%select%'
					AND type_name(c.user_type_id) NOT LIKE '%text%'
					AND (
						c.is_identity = 0
						OR c.is_identity = @includePK
						)
				FOR XML PATH('')
					,TYPE
				).value('.', 'nvarchar(MAX)'), 1, @insertlen, '') + ' AS ''TheData'' FROM ' + quotename(RTRIM(@objname)) + ' WITH(NOLOCK) WHERE 1=1 and ' + @v_Where;

	IF @debug = 1
		SELECT @SQL;

	BEGIN TRY
		EXEC SP_EXECUTESQL @sql;

		SET @sql2 = '  select top ' + convert(VARCHAR(50), @nums) + ' sch.InsertColumn + '' '' + JS.TheData  as [InsertStatement]   from ##tempdata JS   outer apply (    select InsertColumn    from ##temp    ) sch '

		IF @debug = 1
			SELECT @sql2;

		EXEC SP_EXECUTESQL @sql2
	END TRY

	BEGIN CATCH
		SELECT 'Error' = 'Errors below ' + convert(VARCHAR, error_line()) + ' ' + ERROR_MESSAGE()

		UNION ALL

		SELECT 'Error' = @sql

		PRINT @sql
	END CATCH

	BEGIN TRY
		IF @debug = 1
		BEGIN
			SELECT *
			INTO tblspcontents_tempdata
			FROM ##tempdata;

			SELECT @sql2;
		END
	END TRY

	BEGIN CATCH
		SELECT 'Error' = 'Please see Messages for Errors.'
			,'line' = NULL

		UNION ALL

		SELECT ERROR_MESSAGE() message
			,ERROR_LINE() line

		UNION ALL

		SELECT 'Error' = @sql2
			,NULL
	END CATCH
END
GO
IF object_id('Account_Format') IS NOT NULL
	DROP FUNCTION [Account_Format]
GO

CREATE FUNCTION dbo.Account_Format (@AcctCode VARCHAR(20)) /************************************************************************ Function that formats an account number (CODE) using a format string where the question mark (?) represents a number (or character) *************************************************************************/
RETURNS VARCHAR(20)
AS
BEGIN
	DECLARE @FinalFormat VARCHAR(20) /*Return Formatted Account Code*/
	DECLARE @AcceptableNumChars VARCHAR(20)
		,/*string of characters that are recognized as numbers in @AcctFormat*/
		@iFormatLength TINYINT
		,@iAcctLength TINYINT
		,@columncode CHAR(1)
	DECLARE @nextNumber CHAR(1)
		,@AcctFormat VARCHAR(20) = (
			SELECT SAFMT
			FROM PARAM
			WHERE HCHART = 0
			)

	SET @AcctFormat = ltrim(rtrim(@AcctFormat))
	SET @AcctCode = ltrim(rtrim(@AcctCode))
	SET @AcceptableNumChars = '?#$%*' /************************************************************************ This section adds the possibility of using other characters, besides dashes (-) as seperating characters. *************************************************************************/

	IF charindex('-', @AcctFormat) <> 0
	BEGIN
		SET @AcctCode = substring(@AcctCode + '0000000000000000', 1, len(replace(@AcctFormat, '-', '')))
	END

	IF charindex('.', @AcctFormat) <> 0
	BEGIN
		SET @AcctCode = substring(@AcctCode + '0000000000000000', 1, len(replace(@AcctFormat, '.', '')))
	END

	IF charindex(' ', @AcctFormat) <> 0
	BEGIN
		SET @AcctCode = substring(@AcctCode + '0000000000000000', 1, len(replace(@AcctFormat, ' ', '')))
	END

	IF len(@AcctFormat) > 0 /*If the AcctFormat is blank, do not make AcctCode blank*/
	BEGIN
		SET @Acctcode = substring(@AcctCode + '0000000000000000', 1, dbo.AcctTreeFormatCount(@AcctFormat))
	END /********************************************************************************************************** A. Kick out any code that is blank B. Kick out any code that does not have the same number of characters as Question marks in the format C. Kick out any code that doesnt have a format - *** change this so the code gets returned as is. ***********************************************************************************************************/

	IF isnull(@AcctCode, '') <> ''
		AND isnull(@AcctFormat, '') = ''
	BEGIN
		SET @FinalFormat = @AcctCode

		RETURN @FinalFormat
	END

	IF isnull(@AcctCode, '') = ''
		OR (
			isnull(@AcctFormat, '') <> ''
			AND isnull(@AcctCode, '') <> ''
			AND dbo.AcctTreeFormatCount(@AcctFormat) <> len(isnull(@AcctCode, ''))
			)
	BEGIN
		SET @FinalFormat = ''

		RETURN @FinalFormat
	END

	SET @FinalFormat = ''

	SELECT @iFormatLength = len(@AcctFormat)
		,/* Number of char in Format */ @iAcctLength = len(@AcctCode)
		,/* Number of char in Account */ @columncode = left(@AcctFormat, 1)
		,/* First Format char */ @nextNumber = left(@AcctCode, 1) /* First Number or Char in account code */

	WHILE (@iFormatLength > 0)
	BEGIN
		IF charindex(@columncode, @AcceptableNumChars) <> 0 /* if the format character is a question mark, add the next CODE character and increment by 1 */
		BEGIN
			SET @FinalFormat = @FinalFormat + @nextNumber /* add the acct code char to the result */
			SET @iAcctLength = @iAcctLength - 1 /* used up one slot */
			SET @AcctCode = substring(@AcctCode, 2, @iAcctLength) /* reduce the string by 1 */
			SET @nextNumber = left(@AcctCode, 1) /* set the next character from the code */
		END
		ELSE
		BEGIN
			SET @FinalFormat = @FinalFormat + @columncode /* no question mark so add the filler character */
		END /* End If */ /* Get the next value in the Format */

		SET @iFormatLength = @iFormatLength - 1 /* reduce the format length by one*/
		SET @AcctFormat = substring(@AcctFormat, 2, @iFormatLength) /* reduce the format string by taking off the first char */
		SET @columncode = left(@AcctFormat, 1) /* find the next character to test */
	END /* End While Loop */

	RETURN @FinalFormat
END
GO

IF object_id('AcctTreeFormatCount') IS NOT NULL
	DROP FUNCTION [AcctTreeFormatCount]
GO

CREATE FUNCTION dbo.AcctTreeFormatCount (@AcctFormat VARCHAR(20))
	/************************************************************************
 Function that counts the number of question marks in the account format
 *************************************************************************/
RETURNS TINYINT
AS
BEGIN
	DECLARE @QuestionMarkFormat VARCHAR(20)
	DECLARE @AcceptableNumChars VARCHAR(20)
	DECLARE @iLength TINYINT
	DECLARE @iQuestionMark TINYINT /*Return number of question marks in the format*/

	SET @iQuestionMark = 0
	SET @AcceptableNumChars = '?#$%*' /*Add characters to be recognized as numbers*/
	SET @iLength = len(@AcctFormat) --9
	SET @QuestionMarkFormat = @AcctFormat -- same as coming in

	WHILE @iLength > 0
	BEGIN
		IF charindex(left(@QuestionMarkFormat, 1), @AcceptableNumChars) <> 0
		BEGIN
			SET @iQuestionMark = @iQuestionMark + 1
		END

		SET @iLength = @iLength - 1
		SET @QuestionMarkFormat = substring(@QuestionMarkFormat, 2, @iLength)
			/* while loop */
	END

	RETURN @iQuestionMark
END
GO


CREATE
	OR

ALTER FUNCTION dbo.formatdate (@d DATETIME)
RETURNS VARCHAR(22)
AS
BEGIN
	DECLARE @value VARCHAR(22);

	SELECT @value = convert(VARCHAR, @d, 101) + ' ' + CASE
			WHEN len(CONVERT(VARCHAR, datepart(hour, @d))) = 1
				THEN '0' + CONVERT(VARCHAR, datepart(hour, @d))
			ELSE CONVERT(VARCHAR, datepart(hour, @d))
			END + ':' + CASE
			WHEN LEN(CONVERT(VARCHAR, datepart(minute, @d))) = 1
				THEN '0' + CONVERT(VARCHAR, datepart(minute, @d))
			ELSE CONVERT(VARCHAR, datepart(minute, @d))
			END + ':' + CASE
			WHEN LEN(CONVERT(VARCHAR, datepart(second, @d))) = 1
				THEN '0' + CONVERT(VARCHAR, datepart(second, @d))
			ELSE CONVERT(VARCHAR, datepart(second, @d))
			END + ' ' + RIGHT(CONVERT(VARCHAR, @d, 101) + ' ' + STUFF(CONVERT(VARCHAR, @d, 109), 1, 12, ''), 2)

	RETURN @value
END
GO
IF object_id('CalcUnitRent') IS NOT NULL
	DROP FUNCTION [CalcUnitRent]
GO

CREATE FUNCTION dbo.CalcUnitRent (
    @hunit AS NUMERIC(18, 0)
,@asofdt AS DATETIME
)
    RETURNS NUMERIC(21, 2)
AS
BEGIN
	DECLARE @URent NUMERIC(21, 2)

SELECT @URent = sum(cr.destimated * (
    CASE cr.iestimatetype
        WHEN 1
            THEN isnull(cr.dcontractarea, ux.dsqft) * (
                isnull(cr.dcontractarea, ux.dsqft) / (
                CASE la.dsqft
                    WHEN 0
                        THEN 1
                    ELSE la.dsqft
                    END
                )
            )
        WHEN 2
            THEN (
                isnull(cr.dcontractarea, ux.dsqft) / (
                CASE la.dsqft
                    WHEN 0
                        THEN 1
                    ELSE la.dsqft
                    END
                )
            )
        END
    ) / (
                        CASE cr.iAmountPeriod
                            WHEN 0
                                THEN 12
                            WHEN 1
                                THEN 3
                            WHEN 2
                                THEN 1
                            END
                        ))
FROM unit u
         INNER JOIN unitxref ux ON ux.hunit = u.hmy
         LEFT OUTER JOIN (
    SELECT ux.htenant htenant
         ,sum(ux.dsqft) dsqft
    FROM unitxref ux
    WHERE 1 = 1
      AND @asofdt BETWEEN ux.dtleasefrom
        AND isnull(ux.dtleaseto, @asofdt)
    GROUP BY ux.htenant
) la ON la.htenant = ux.htenant
         INNER JOIN CommSchedule cs ON cs.hamendment = ux.hamendment
    AND cs.htenant IS NOT NULL
    AND cs.itype = 2
         INNER JOIN CamRule cr ON cr.hschedule = cs.hmy
         INNER JOIN chargtyp ct ON ct.hmy = cr.hchargecode
    AND ct.itype = 2
WHERE u.hmy = @hunit
  AND @asofdt BETWEEN ux.dtleasefrom
    AND isnull(ux.dtleaseto, @asofdt)
  AND @asofdt BETWEEN cs.dtfrom
    AND isnull(cs.dtto, @asofdt)
  AND @asofdt BETWEEN cr.dtfrom
    AND isnull(cr.dtto, @asofdt)

    RETURN @URent
END
GO
IF object_id('Commcrmleasingagents') IS NOT NULL
	DROP FUNCTION [Commcrmleasingagents]
GO

CREATE FUNCTION dbo.CommCrmLeasingAgents (@hprospect NUMERIC(18, 0))
    RETURNS VARCHAR(2000)
AS
BEGIN
	DECLARE @u VARCHAR(2000)
		,@la_name VARCHAR(100)
		,@l INT

	SET @u = ''

	DECLARE cr CURSOR FAST_FORWARD
	FOR
SELECT p.sfirstname + ' ' + p.ulastname laname
FROM CommProspectLeasingAgent cpla
         JOIN person p ON p.hmy = cpla.hMyPerson
WHERE cpla.hMy = @hprospect
ORDER BY p.sfirstname

    OPEN cr

	FETCH NEXT
FROM cr
INTO @la_name

    WHILE @@FETCH_STATUS = 0
BEGIN
		SET @u = Ltrim(Rtrim(@u)) + ', ' + Ltrim(Rtrim(@la_name))

		FETCH NEXT
		FROM cr
		INTO @la_name
END

CLOSE cr

    DEALLOCATE cr

	SET @l = Len(@u)

	RETURN Substring(@u, 2, @l)
END
GO

IF object_id('SM2_GetReportBatch') IS NOT NULL
	DROP PROCEDURE [SM2_GetReportBatch]
GO

CREATE PROCEDURE [dbo].[SM2_GetReportBatch] (@BatchSize INT)
AS
DECLARE @RunningRegular INT
	,@RunningLong INT
	,@UpToRegular INT
	,@UpToLong INT;
DECLARE @ResultsTable TABLE (hMy NUMERIC(18, 0));

BEGIN
	SET NOCOUNT ON;

	--
	-- get counts for currently running regular and long
	--
	SELECT @RunningRegular = isnull(sum(CASE
					WHEN l.sFileName IS NULL
						THEN 1
					ELSE 0
					END), 0)
		,@RunningLong = isnull(sum(CASE
					WHEN l.sFileName IS NULL
						THEN 0
					ELSE 1
					END), 0)
	FROM dbo.request_que r
	LEFT JOIN dbo.ConductorLongRep l ON l.sFileName = dbo.SM2_GetFileName(r.SSCRIPT)
	WHERE ISTATUS = 1

	--
	-- get how many of each would be allowed to run
	--
	SELECT TOP 1 @UpToRegular = isnull(iMaxThreadReg, 3) - @RunningRegular
		,@UpToLong = isnull(iMaxThreadLong, 1) - @RunningLong
	FROM dbo.ConductorConfig

	IF @UpToRegular IS NULL
		SELECT @UpToRegular = 3 - @RunningRegular
			,@UpToLong = 1 - @RunningLong;

	IF @UpToRegular < 0
		SET @UpToRegular = 0

	IF @UpToLong < 0
		SET @UpToLong = 0

	--
	-- We don't have separate batch types for regular and long running reports.
	-- The split happens on the agent.
	-- So at the end we'll lump together the regular and long running to create the batch.
	-- It is not optimal (or fair).
	-- But it should be correct as far as making sure that the global limits are not exceeded.
	--
	INSERT INTO @ResultsTable (hMy)
	SELECT TOP (@UpToRegular) hMy
	FROM dbo.request_que
	WHERE iStatus = 0
		AND DTSCHEDULE <= GETDATE()
		AND dbo.SM2_GetFileName(SSCRIPT) NOT IN (
			SELECT sFileName
			FROM dbo.ConductorLongRep
			)
	ORDER BY hMy

	INSERT INTO @ResultsTable (hMy)
	SELECT TOP (@UpToLong) hMy
	FROM dbo.request_que
	WHERE iStatus = 0
		AND DTSCHEDULE <= GETDATE()
		AND dbo.SM2_GetFileName(SSCRIPT) IN (
			SELECT sFileName
			FROM dbo.ConductorLongRep
			)
	ORDER BY hMy

	SET NOCOUNT OFF;

	--
	-- Send out the batch (candidate)
	--
	SELECT TOP (@BatchSize) hMy
	FROM @ResultsTable
	ORDER BY hMy
END
GO

IF object_id('SM2_GetFileName') IS NOT NULL
	DROP FUNCTION [SM2_GetFileName]
GO

CREATE FUNCTION [dbo].[SM2_GetFileName] (@Path NVARCHAR(MAX))
RETURNS NVARCHAR(MAX)
AS
BEGIN
	DECLARE @FileName NVARCHAR(MAX)
	DECLARE @ReversedPath NVARCHAR(MAX)
	DECLARE @LastSlashIndex INT

	SET @ReversedPath = REVERSE(@Path)
	SET @LastSlashIndex = CHARINDEX('\', @ReversedPath)

	IF (@LastSlashIndex = 0)
		SET @FileName = @Path
	ELSE
		SELECT @FileName = RIGHT(@Path, @LastSlashIndex - 1)

	RETURN @FileName
END
GO


SELECT ca.hMy AmendmentId
	,ca.hTenant TenantId
	,ca.dtStart StartDate
	,CASE
		WHEN ca.itype IN (
				3
				,6
				,15
				)
			AND ca.istatus IN (
				0
				,1
				,3
				)
			THEN ca.dtend
		ELSE isNull(ca.dtMoveOut, ca.dtEnd)
		END EndDate
	,ca.iTerm Term
	,isNull(ca.iType, 0) iType
	,isNull(ca.iProposalType, 0) iProposalType
	,isNull(ca.iStatus, 0) iStatus
	,ca.sDesc Description
	,ca.iSequence Sequence
	,cat.Type Type
	,cas.sStatus STATUS
	,cds.sCode Stage
	,dbo.CommAmendmentUnits(ca.hMy) UnitCodeList
FROM CommAmendments ca
 JOIN CommAmendmentType cat ON (ca.iType = cat.iType)
 JOIN CommAmendmentStatus cas ON (ca.iStatus = cas.iStatus)
LEFT OUTER JOIN CommDealStatus cds ON (ca.hProposalStage = cds.hmy)
WHERE 1 = 1
	AND ca.hTenant = 38165
	-- AND ca.iType NOT IN (
	-- 	13
	-- 	,14
	-- 	)
ORDER BY ca.dtStart
	,ca.iSequence
	,ca.hmy
GO

SELECT t.hMyPerson "Id"
	,t.sCode "Code"
	,t.sFirstName "FirstName"
	,t.sLastName "LastName"
	,t.sMiddleName "MiddleName"
	,t.sSalutation "Salutation"
	,t.sAddr1 "Address1"
	,t.sAddr2 "Address2"
	,per.sAddr3 "Address3"
	,per.sAddr4 "Address4"
	,t.hCountry "CountryId"
	,t.sExtraAddrLine "ExtraAddressLine"
	,t.sCity "City"
	,t.sState "State"
	,t.sZipCode "ZipCode"
	,t.sFedId "GovernmentId"
	,t.bGets1099 "Gets1099"
	,t.iStatus "Status"
	,t.hProperty "PropertyId"
	,t.hUnit "UnitId"
	,t.sRent "Rent"
	,t.dtLeaseFrom "LeaseFrom"
	,t.dtLeaseTo "LeaseTo"
	,t.dtMoveIn "MoveIn"
	,t.dtMoveOut "MoveOut"
	,t.dtNotice "NoticeDate"
	,t.dtRenewDate "LastRenewalDate"
	,t.dtSignDate "LeaseSignDate"
	,t.bNoPayments "PaymentType"
	,t.bAch "PayableType"
	,t.bACHOptOut "AchOptOut"
	,t.sEmail "Email"
	,t.sEmail2 "Email2"
	,t.PUTCode "myPropertyUnitTenantCode"
	,t.SLATEMIN "LateFeeMinimum"
	,t.SLATEPERDAY "LateFeePerDay"
	,t.ILATETYPE "LateFeeType"
	,t.ILATEGRACE "LateFeeGraceDays"
	,t.DLATEPERCENT "LateFeePercent"
	,t.iLateGrace2 "LateFeeGraceDays2"
	,t.dLateAmt2 "LateFeeAmount2"
	,t.dLatePercent2 "LateFeePercent2"
	,t.dLateAmtMax "LateFeeMax"
	,t.dLatePercentMax "LateFeeMaxPercent"
	,t.iLateDaysMax "LateFeeMaxDays"
	,t.iLateTypeMax "LateFeeAmountTypeMax"
	,t.iLateType2 "LateFeeAmountType2"
	,t.dLateMinDueAmt "LateFeeMinDue"
	,t.DLEASEGROSSSQFT "LeaseGrossSqft"
	,t.sUnitCode "myUnitCode"
	,t.bMovedOut "HasDepositAccounting"
	,t.sMaintNotes "MaintenanceNotes"
	,p.sCode "myPropertyCode"
	,t.iDueDay "DueDay"
	,t.sLastMonth "LateMonthDeposit"
	,t.dInterest "DepositInterest"
	,t.iLeaseType "LeaseDescription"
	,t.hRoom "RoomId"
	,t.hBed "BedId"
	,t.sRoomCode "RoomCode"
	,t.sBedCode "BedCode"
	,t.bBillToCustomer "IsBillToCustomer"
	,t.iRiskType "ForecastingRiskType"
	,t.BMTCSSUBSIDIZED "IsMTCSSubsidized"
	,p.hLegalEntity "myLegalEntity"
	,per.hPrefLanguage "PrefLanguage"
	,per.iPrefCorrespondence "PrefCorrespondence"
	,per.iPayablePaymentMethod "PayablePaymentMethod"
	,t.sFields0 "Field0"
	,t.sFields1 "Field1"
	,t.sFields2 "Field2"
	,t.sFields3 "Field3"
	,t.sFields4 "Field4"
	,t.sFields5 "Field5"
	,t.sFields6 "Field6"
	,t.sFields7 "Field7"
	,t.sFields8 "Field8"
	,t.sFields9 "Field9"
	,t.sFields10 "Field10"
	,t.sFields11 "Field11"
	,t.sFields12 "Field12"
	,t.sFields13 "Field13"
	,t.sLeaseName "LeaseName"
	,t.sLeaseCompany "LeaseCompany"
	,t.sLeaseAddr1 "LeaseAddr1"
	,t.sLeaseAddr2 "LeaseAddr2"
	,t.sLeaseAddr3 "LeaseAddr3"
	,t.sLeaseCity "LeaseCity"
	,t.sLeaseState "LeaseState"
	,t.sLeaseZipCode "LeaseZipCode"
	,t.sLeaseBusType "LeaseBusType"
	,t.iLeaseOvgMonth "LeaseOvgMonth"
	,t.bLeasePayRent "LeasePayRent"
	,t.sLeaseField10 "LeaseFields0"
	,t.sLeaseField11 "LeaseFields1"
	,t.sLeaseField12 "LeaseFields2"
	,t.sLeaseField13 "LeaseFields3"
	,t.sLeaseField14 "LeaseFields4"
	,t.sLeaseField15 "LeaseFields5"
	,t.sLeaseField16 "LeaseFields6"
	,t.sLeaseField20 "LeaseFields7"
	,t.sLeaseField21 "LeaseFields8"
	,t.sLeaseField22 "LeaseFields9"
	,t.sLeaseField23 "LeaseFields10"
	,t.sLeaseField24 "LeaseFields11"
	,t.sLeaseField25 "LeaseFields12"
	,t.sLeaseField26 "LeaseFields13"
	,t.sLeaseField30 "LeaseFields14"
	,t.sLeaseField31 "LeaseFields15"
	,t.sLeaseField32 "LeaseFields16"
	,t.sLeaseField33 "LeaseFields17"
	,t.sLeaseField34 "LeaseFields18"
	,t.sLeaseField35 "LeaseFields19"
	,t.sLeaseField36 "LeaseFields20"
	,t.iType "Type"
	,t.hCustomer "CustomerId"
	,t.sWebsite "Website"
	,t.bSepInc "SeperateIncrease"
	,t.bBaseRel "BaseRelative"
	,t.hBillCurrency "BillCurrencyId"
	,t.hLeaseCurrency "LeaseCurrencyId"
	,t.iBlockInvoice "BlockInvoice"
	,t.dtContractEndDate "ContractEndDate"
	,t.iMethodOfPayment "MethodOfPayment"
	,t.hTranType "VatTranTypeId"
	,t.hCurExchRateType "CurrencyExchangeRateTypeId"
	,t.IINTERESTFREE "LatefeeInterestFree"
	,t.DLATEPERDAY "LatefeeAmountPerDay"
	,t.HBANK "LatefeeBankId"
	,t.DADJUSTMENT "LatefeeAdjustment"
	,t.CMINTHRESHOLD "LatefeeMinThreshold"
	,t.CMAXTHRESHOLD "LatefeeMaxThreshold"
	,t.DMINPERCENTAGE "LatefeeminPercentage"
	,t.DMAXPERCENTAGE "LatefeemaxPercentage"
	,t.ILATEFEECALCBASIS "myLatefeeCalcBasis"
	,t.hVendor "LandlordId"
	,t.sRegNum "VatRegistrationNumber"
	,t.dPropTaxRecovery "PropertyTaxRecoveryPercentage"
	,t.dLFFactor "LatefeeFactor"
	,t.dLFAdditionalFee "LFAdditionalFee"
	,t.hLeasingAgent "LeasingAgent"
	,t.hBroker "Broker"
FROM tenant t
INNER JOIN property p ON p.hMy = t.hProperty
INNER JOIN person per ON per.hMy = t.hMyPerson
WHERE 1 = 1
	AND t.hMyPerson = 38165
GO

SELECT t.hUserCreatedBy UserCreated
	,t.hUserModifiedBy UserModified
	,t.dtCreated DateCreated
	,t.dtLastModified DateModified
FROM tenant t
INNER JOIN property p ON p.hMy = t.hProperty
INNER JOIN person per ON per.hMy = t.hMyPerson
WHERE 1 = 1
	AND t.hMyPerson = 38165
GO

SELECT ct.hmy "Id"
	,ct.hTenant "TenantId"
	,ct.hCommICS "CommICS"
	,ct.hLeaseType "LeaseTypeId"
	,ct.iLeaseStatus "Status"
	,ct.hSalesCategory "SalesCategoryId"
	,ct.hDeal "DealId"
	,ct.bAnchor "IsAnchor"
	,ct.bClientLiability "IsOwnerLiability"
	,ct.bShowOpeningChargesLink "ShowOpeningChargesLink"
	,ct.bChargeLFOnUnpaid "ChargeLFOnUnpaid"
	,ct.iDaysInYear "DaysInYear"
	,ct.bIsGuaranteeRequired "IsGuaranteeRequired"
	,ct.hSalesCurrency "SalesCurrencyId"
	,ct.hSalesCurExchRateType "SalesCurrExcRateId"
	,ct.hFunding "FundingId"
	,ct.bEnableEdit "EnableEdit"
	,ct.hFranchisee "FranchiseeId"
	,isNull(ct.hChargeIncreaseType, - 1) "ChargeIncreaseType"
	,ct.bIsAtRiskTenant "IsAtRiskTenant"
	,ct.bIsCMLLease "IsCMLLease"
	,ct.bCommFavoredTenant "IsCommFavoredTenant"
	,ct.hCompany "CompanyId"
FROM CommTenant ct
WHERE 1 = 1
	AND ct.hTenant = 38165
GO


