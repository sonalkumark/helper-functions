create view getNewID as select newid() as new_id

CREATE OR ALTER FUNCTION GENERATENEWID() RETURNS NVARCHAR(36)
AS BEGIN
	RETURN (SELECT CAST(new_id AS NVARCHAR(36)) FROM getNewID);
END

-- Requires SQL Server 2017+ (STRING_AGG, JSON functions)
-- Set database compatibility level to 140 or higher.
-- ALTER DATABASE YourDb SET COMPATIBILITY_LEVEL = 140;

CREATE OR ALTER FUNCTION dbo.JsonDeepMerge
(
    @Existing NVARCHAR(MAX),   -- existing JSON fragment (object / array / scalar)
    @Incoming NVARCHAR(MAX)    -- incoming JSON fragment (object / array / scalar)
)
RETURNS NVARCHAR(MAX)
AS
BEGIN
    DECLARE @Result NVARCHAR(MAX);

    -- If incoming isn't JSON, it's a scalar override.
    IF ISJSON(@Incoming) <> 1
        RETURN @Incoming;

    -- Normalize NULL existing
    IF @Existing IS NULL SET @Existing = N'';

    ------------------------------------------------------------
    -- Handle ARRAYS
    ------------------------------------------------------------
    IF LEFT(LTRIM(@Incoming),1) = '['
    BEGIN
        -- If the incoming array isn't an array of OBJECTS, we REPLACE the whole array.
        -- (Rules 1-3 only make sense for objects.)
        IF NOT EXISTS (SELECT 1 FROM OPENJSON(@Incoming) WHERE [type] = 5)
            RETURN @Incoming;

        -- Existing array: if not a valid JSON array, treat as empty.
        DECLARE @ExistingArray NVARCHAR(MAX) =
            CASE WHEN ISJSON(@Existing) = 1 AND LEFT(LTRIM(@Existing),1)='[' THEN @Existing ELSE N'[]' END;

        -- Existing objects by _id
        DECLARE @ex TABLE(
            pos INT IDENTITY(1,1),
            _id NVARCHAR(50) NULL,
            obj NVARCHAR(MAX) NOT NULL
        );

        INSERT INTO @ex(_id, obj)
        SELECT
            JSON_VALUE(value,'$._id'),
            JSON_QUERY(value)
        FROM OPENJSON(@ExistingArray)
        WHERE [type] = 5;

        -- Ensure every existing object has _id
        DECLARE @i INT = 1, @n INT = (SELECT COUNT(*) FROM @ex);
        WHILE @i <= @n
        BEGIN
            DECLARE @_ex_id NVARCHAR(50), @_ex_obj NVARCHAR(MAX);
            SELECT @_ex_id = _id, @_ex_obj = obj FROM @ex WHERE pos = @i;

            IF @_ex_id IS NULL
            BEGIN
                SET @_ex_id = CAST(dbo.GENERATENEWID() AS NVARCHAR(36));
                SET @_ex_obj = JSON_MODIFY(@_ex_obj, '$._id', @_ex_id);
                UPDATE @ex SET _id = @_ex_id, obj = @_ex_obj WHERE pos = @i;
            END

            SET @i += 1;
        END

        -- Seed result with existing items
        DECLARE @res TABLE(
            pos INT,
            _id NVARCHAR(50) PRIMARY KEY,
            obj NVARCHAR(MAX) NOT NULL
        );

        INSERT INTO @res(pos, _id, obj)
        SELECT pos, _id, obj FROM @ex;

        -- Incoming objects
        DECLARE @in TABLE(
            ord INT IDENTITY(1,1),
            obj NVARCHAR(MAX) NOT NULL
        );

        INSERT INTO @in(obj)
        SELECT JSON_QUERY(value)
        FROM OPENJSON(@Incoming)
        WHERE [type] = 5;

        -- Process incoming one by one
        DECLARE @k INT = 1, @kmax INT = (SELECT COUNT(*) FROM @in);
        WHILE @k <= @kmax
        BEGIN
            DECLARE @_in_obj NVARCHAR(MAX) = (SELECT obj FROM @in WHERE ord = @k);

            -- If _deleted = true and has _id → remove from @res
            IF JSON_VALUE(@_in_obj, '$._deleted') = N'true'
            BEGIN
                DECLARE @_del_id NVARCHAR(50) = JSON_VALUE(@_in_obj, '$._id');
                IF @_del_id IS NOT NULL
                    DELETE FROM @res WHERE _id = @_del_id;

                SET @k += 1;
                CONTINUE;
            END

            -- Ensure _id exists for incoming object
            DECLARE @_id NVARCHAR(50) = JSON_VALUE(@_in_obj, '$._id');
            IF @_id IS NULL
            BEGIN
                SET @_id = CAST(dbo.GENERATENEWID() AS NVARCHAR(36));
                SET @_in_obj = JSON_MODIFY(@_in_obj, '$._id', @_id);
            END

            -- Find existing with same _id
            IF EXISTS (SELECT 1 FROM @res WHERE _id = @_id)
            BEGIN
                DECLARE @_ex_obj2 NVARCHAR(MAX) = (SELECT obj FROM @res WHERE _id = @_id);
                DECLARE @_merged NVARCHAR(MAX) = dbo.JsonDeepMerge(@_ex_obj2, @_in_obj);
                UPDATE @res SET obj = @_merged WHERE _id = @_id;
            END
            ELSE
            BEGIN
                -- New item: append to end (after current max position)
                DECLARE @_maxpos INT = ISNULL((SELECT MAX(pos) FROM @res), 0);
                INSERT INTO @res(pos, _id, obj) VALUES (@_maxpos + 1, @_id, @_in_obj);
            END

            SET @k += 1;
        END

        -- Rebuild array preserving order
        DECLARE @ArrayOut NVARCHAR(MAX) =
            N'[' + ISNULL((
                SELECT STRING_AGG(obj, N',') WITHIN GROUP (ORDER BY pos)
                FROM @res
            ), N'') + N']';

        RETURN @ArrayOut;
    END

    ------------------------------------------------------------
    -- Handle OBJECTS
    ------------------------------------------------------------
    IF LEFT(LTRIM(@Incoming),1) = '{'
    BEGIN
        -- Start from existing object if valid, else empty.
        SET @Result = CASE WHEN ISJSON(@Existing)=1 AND LEFT(LTRIM(@Existing),1)='{' THEN @Existing ELSE N'{}' END;

        -- Ensure _id exists (rule 1) on the RESULT container
        IF JSON_VALUE(@Result, '$._id') IS NULL
            SET @Result = JSON_MODIFY(@Result, '$._id', CAST(dbo.GENERATENEWID() AS NVARCHAR(36)));

        -- Walk incoming keys (without cursor; table + WHILE)
        DECLARE @keys TABLE(
            rn INT IDENTITY(1,1),
            [key] NVARCHAR(4000),
            value NVARCHAR(MAX),
            [type] INT
        );

        INSERT INTO @keys([key], value, [type])
        SELECT [key], value, [type]
        FROM OPENJSON(@Incoming);

        DECLARE @r INT = 1, @rmax INT = (SELECT COUNT(*) FROM @keys);

        WHILE @r <= @rmax
        BEGIN
            DECLARE @kName NVARCHAR(4000), @kVal NVARCHAR(MAX), @kType INT;
            SELECT @kName=[key], @kVal=value, @kType=[type] FROM @keys WHERE rn = @r;

            IF @kType IN (4,5) -- array(4) or object(5)
            BEGIN
                DECLARE @ExistingChild NVARCHAR(MAX) = JSON_QUERY(@Result, '$.' + QUOTENAME(@kName,'"'));
                DECLARE @MergedChild NVARCHAR(MAX) = dbo.JsonDeepMerge(@ExistingChild, @kVal);
                SET @Result = JSON_MODIFY(@Result, '$.' + QUOTENAME(@kName,'"'), JSON_QUERY(@MergedChild));
            END
            ELSE
            BEGIN
                -- scalars: overwrite
				IF LOWER(@kVal) IN ('true', 'false') 
				BEGIN 
					SET @Result = JSON_MODIFY(@Result, '$.' + QUOTENAME(@kName,'"'), CASE WHEN LOWER(@kVal) = 'true' THEN CAST(1 AS BIT) WHEN LOWER(@kVal) = 'false' THEN CAST(0 AS BIT) ELSE NULL END);
				END
				ELSE IF TRY_CAST(@kVal AS BIGINT) IS NOT NULL
				BEGIN
					SET @Result = JSON_MODIFY(@Result, '$.' + QUOTENAME(@kName,'"'), TRY_CAST(@kVal AS BIGINT));
				END
				ELSE IF TRY_CAST(@kVal AS DECIMAL(25, 5)) IS NOT NULL
				BEGIN
					SET @Result = JSON_MODIFY(@Result, '$.' + QUOTENAME(@kName,'"'), TRY_CAST(@kVal AS DECIMAL(25, 5)));
				END
				ELSE
				BEGIN
					SET @Result = JSON_MODIFY(@Result, '$.' + QUOTENAME(@kName,'"'), @kVal);
				END
            END

            SET @r += 1;
        END

        -- If incoming object itself had _deleted=true, that only has meaning when
        -- this object is inside an array. At top level we keep the merged object.
        RETURN @Result;
    END

    ------------------------------------------------------------
    -- Fallback (shouldn't hit): treat as scalar
    ------------------------------------------------------------
    RETURN @Incoming;
END
GO
