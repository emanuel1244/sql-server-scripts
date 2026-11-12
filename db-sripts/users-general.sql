
-- Author: ecamargo
-- Date: 20/08/2025
-- Description: Retrieves user information by email.

CREATE PROCEDURE [dbo].[GetUserInfoByEmail]
    @pEmail NVARCHAR(254)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @UserId BIGINT;

    EXEC [dbo].[GetUserIdByEmail]
        @pEmail,
        @UserId OUTPUT;

    IF (@UserId IS NULL OR @UserId <= 0)
    BEGIN
        SELECT 101000 AS errorCode; -- USER_NOT_FOUND
    END
    ELSE
    BEGIN
        SELECT
            UP.UserId,
            UP.FirstName AS Name,
            UP.LastName,
            UP.Birthday,
            UP.IsEnabled AS Enabled,
            UP.UpdatedAt,
            UP.CreatedAt,
            C.Name AS CountryName,
            C.Code AS CountryCode,
            ST.Name AS StateName,
            RG.Name AS RegionName,
            LC.Name AS LocalityName,
            @pEmail AS Email,
            FC.UUID AS ClubUUID,
            CR.Name AS RoleName,
            MA.Url AS ProfileImageUrl,
            UT.Type AS UserType
        FROM UserProfiles UP
        INNER JOIN UserTypes UT
            ON UT.UserTypeId = UP.UserTypeId
            AND UT.DeletedAt IS NULL
        LEFT JOIN FootballClubs FC
            ON FC.ClubId = UP.ClubId
            AND FC.DeletedAt IS NULL
        LEFT JOIN UserAccounts UA
            ON UA.UserId = UP.UserId
            AND UA.DeletedAt IS NULL
        LEFT JOIN ClubRoles CR
            ON CR.ClubRoleId = UA.ClubRoleId
            AND CR.DeletedAt IS NULL
        LEFT JOIN UserLocalities UL
            ON UL.UserId = UP.UserId
            AND UL.DeletedAt IS NULL
        LEFT JOIN Localities LC
            ON LC.LocalityId = UL.LocalityId
            AND LC.DeletedAt IS NULL
        INNER JOIN Regions RG
            ON RG.RegionId = LC.RegionId
            AND RG.DeletedAt IS NULL
        LEFT JOIN Countries C
            ON UP.NationalityId = C.CountryId
            AND C.DeletedAt IS NULL
        LEFT JOIN UserAddresses UAD
            ON UP.AddressId = UAD.AddressId
            AND UAD.DeletedAt IS NULL
        LEFT JOIN Cities CT
            ON UAD.CityId = CT.CityId
            AND CT.DeletedAt IS NULL
        LEFT JOIN States ST
            ON CT.StateId = ST.StateId
            AND ST.DeletedAt IS NULL
        LEFT JOIN UserProfileImages UPI
            ON UPI.AccountId = UA.AccountId
            AND UPI.IsPrimary = 1
            AND UPI.DeletedAt IS NULL
        LEFT JOIN MediaAssets MA
            ON MA.MediaAssetId = UPI.MediaAssetId
            AND MA.DeletedAt IS NULL
        WHERE UP.UserId = @UserId
          AND UP.DeletedAt IS NULL;
    END;
END;
RETURN 0;
GO


-- Author: ecamargo
-- Date: 10/15/2025
-- Description: Retrieves user address information by email.

CREATE PROCEDURE [dbo].[GetUserAddressInfo]
    @pEmail NVARCHAR(254)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @UserId BIGINT;

    EXEC [dbo].[GetUserIdByEmail]
        @pEmail,
        @UserId OUTPUT;

    IF (@UserId IS NULL OR @UserId <= 0)
    BEGIN
        SELECT 101000 AS errorCode; -- USER_NOT_FOUND
    END
    ELSE
    BEGIN
        SELECT
            UAD.AddressLine1 AS Address1,
            UAD.AddressLine2 AS Address2,
            UAD.PostalCode AS ZipCode,
            UAD.Longitude,
            UAD.Latitude,
            CT.Name AS CityName,
            ST.Name AS StateName,
            CO.Name AS CountryName
        FROM UserProfiles UP
        LEFT JOIN UserAddresses UAD
            ON UP.AddressId = UAD.AddressId
            AND UAD.DeletedAt IS NULL
        LEFT JOIN Cities CT
            ON UAD.CityId = CT.CityId
            AND CT.DeletedAt IS NULL
        LEFT JOIN States ST
            ON ST.StateId = CT.StateId
            AND ST.DeletedAt IS NULL
        LEFT JOIN Countries CO
            ON CO.CountryId = ST.CountryId
            AND CO.DeletedAt IS NULL
        WHERE UP.UserId = @UserId
          AND UP.DeletedAt IS NULL;
    END;
END;
RETURN 0;
GO


-- Author: ecamargo
-- Date: 10/15/2025
-- Description: Retrieves a list of users with search and pagination.

CREATE PROCEDURE [dbo].[GetUsers]
    @pOffset INT = 0,
    @pLimit INT = 10,
    @pRole NVARCHAR(100) = NULL,
    @pSearchText NVARCHAR(254) = '',
    @pOrderValue NVARCHAR(100) = 'username',
    @pDirection NVARCHAR(10) = 'ASC',
    @pIncludeDisabled BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @UserCount BIGINT;

    SELECT @UserCount = COUNT(UserId)
    FROM UserProfiles
    WHERE DeletedAt IS NULL;

    IF (@pLimit * @pOffset > @UserCount)
    BEGIN
        SELECT 101004 AS errorCode; -- NO_USERS_FOUND
    END
    ELSE
    BEGIN
        ;WITH FilteredUsers AS
        (
            SELECT UP.UserId
            FROM UserProfiles UP
            INNER JOIN UserAccounts UA
                ON UA.UserId = UP.UserId
                AND UA.DeletedAt IS NULL
            LEFT JOIN Countries C
                ON UP.NationalityId = C.CountryId
                AND C.DeletedAt IS NULL
            LEFT JOIN UserContactInfo UCI
                ON UCI.UserId = UP.UserId
                AND UCI.DeletedAt IS NULL
            LEFT JOIN ClubRoles CR
                ON CR.ClubRoleId = UA.ClubRoleId
                AND CR.DeletedAt IS NULL
            INNER JOIN ContactInfoTypes CIT
                ON CIT.ContactInfoTypeId = UCI.ContactInfoTypeId
                AND CIT.DeletedAt IS NULL
                AND CIT.Name = 'Email'
            WHERE UP.DeletedAt IS NULL
                AND (@pRole IS NULL OR CR.Name = @pRole)
                AND
                (
                    @pSearchText = ''
                    OR UP.FirstName LIKE @pSearchText
                    OR UP.LastName LIKE @pSearchText
                    OR CONCAT(UP.FirstName, ' ', UP.LastName) LIKE @pSearchText
                    OR UCI.Value LIKE @pSearchText
                    OR C.Name LIKE @pSearchText
                    OR CR.Name LIKE @pSearchText
                )
                AND
                (
                    (@pIncludeDisabled = 0 AND UP.IsEnabled = 1)
                    OR @pIncludeDisabled = 1
                )
            ORDER BY
                CASE WHEN @pOrderValue = 'username'
                    AND @pDirection = 'ASC' THEN UP.FirstName END ASC,
                CASE WHEN @pOrderValue = 'username'
                    AND @pDirection = 'DESC' THEN UP.FirstName END DESC,
                CASE WHEN @pOrderValue = 'email'
                    AND @pDirection = 'ASC' THEN UCI.Value END ASC,
                CASE WHEN @pOrderValue = 'email'
                    AND @pDirection = 'DESC' THEN UCI.Value END DESC,
                CASE WHEN @pOrderValue = 'country'
                    AND @pDirection = 'ASC' THEN C.Name END ASC,
                CASE WHEN @pOrderValue = 'country'
                    AND @pDirection = 'DESC' THEN C.Name END DESC,
                CASE WHEN @pOrderValue = 'status'
                    AND @pDirection = 'DESC' THEN UP.IsEnabled END ASC,
                CASE WHEN @pOrderValue = 'status'
                    AND @pDirection = 'ASC' THEN UP.IsEnabled END DESC,
                CASE WHEN @pOrderValue = 'appRole'
                    AND @pDirection = 'ASC' THEN CR.Name END ASC,
                CASE WHEN @pOrderValue = 'appRole'
                    AND @pDirection = 'DESC' THEN CR.Name END DESC
            OFFSET @pLimit * @pOffset ROWS
            FETCH NEXT @pLimit ROWS ONLY
        )
        SELECT
            UP.UserId,
            COALESCE(UP.FirstName, '') AS FirstName,
            COALESCE(UP.LastName, '') AS LastName,
            UP.Birthday,
            UP.IsEnabled,
            UP.UpdatedAt,
            UP.DeletedAt,
            UP.CreatedAt,
            C.Name AS CountryName,
            C.Code AS CountryCode,
            UAD.AddressLine1,
            UAD.AddressLine2,
            UAD.PostalCode,
            UAD.Longitude,
            UAD.Latitude,
            CT.Name AS CityName,
            ST.Name AS StateName,
            UCI.Value AS Email,
            FC.UUID AS ClubUUID,
            CR.Name AS RoleName,
            MA.Url AS ProfileImageUrl
        FROM UserProfiles UP
        INNER JOIN UserAccounts UA
            ON UA.UserId = UP.UserId
            AND UA.DeletedAt IS NULL
        LEFT JOIN Countries C
            ON UP.NationalityId = C.CountryId
            AND C.DeletedAt IS NULL
        LEFT JOIN UserAddresses UAD
            ON UP.AddressId = UAD.AddressId
            AND UAD.DeletedAt IS NULL
        LEFT JOIN Cities CT
            ON UAD.CityId = CT.CityId
            AND CT.DeletedAt IS NULL
        LEFT JOIN States ST
            ON CT.StateId = ST.StateId
            AND ST.DeletedAt IS NULL
        LEFT JOIN UserContactInfo UCI
            ON UCI.UserId = UP.UserId
            AND UCI.DeletedAt IS NULL
        LEFT JOIN FootballClubs FC
            ON FC.ClubId = UP.ClubId
            AND FC.DeletedAt IS NULL
        LEFT JOIN ClubRoles CR
            ON CR.ClubRoleId = UA.ClubRoleId
            AND CR.DeletedAt IS NULL
        LEFT JOIN UserProfileImages UPI
            ON UPI.AccountId = UA.AccountId
            AND UPI.IsPrimary = 1
            AND UPI.DeletedAt IS NULL
        LEFT JOIN MediaAssets MA
            ON MA.MediaAssetId = UPI.MediaAssetId
            AND MA.DeletedAt IS NULL
        INNER JOIN ContactInfoTypes CIT
            ON CIT.ContactInfoTypeId = UCI.ContactInfoTypeId
            AND CIT.Name = 'Email'
        WHERE EXISTS
        (
            SELECT 1
            FROM FilteredUsers FU
            WHERE FU.UserId = UP.UserId
        )
        AND UP.DeletedAt IS NULL
        ORDER BY
            CASE WHEN @pOrderValue = 'username'
                AND @pDirection = 'ASC' THEN UP.FirstName END ASC,
            CASE WHEN @pOrderValue = 'username'
                AND @pDirection = 'DESC' THEN UP.FirstName END DESC,
            CASE WHEN @pOrderValue = 'email'
                AND @pDirection = 'ASC' THEN UCI.Value END ASC,
            CASE WHEN @pOrderValue = 'email'
                AND @pDirection = 'DESC' THEN UCI.Value END DESC,
            CASE WHEN @pOrderValue = 'country'
                AND @pDirection = 'ASC' THEN C.Name END ASC,
            CASE WHEN @pOrderValue = 'country'
                AND @pDirection = 'DESC' THEN C.Name END DESC,
            CASE WHEN @pOrderValue = 'status'
                AND @pDirection = 'DESC' THEN UP.IsEnabled END ASC,
            CASE WHEN @pOrderValue = 'status'
                AND @pDirection = 'ASC' THEN UP.IsEnabled END DESC,
            CASE WHEN @pOrderValue = 'appRole'
                AND @pDirection = 'ASC' THEN CR.Name END ASC,
            CASE WHEN @pOrderValue = 'appRole'
                AND @pDirection = 'DESC' THEN CR.Name END DESC;
    END;
END;
RETURN 0;
GO


-- Author: ecamargo
-- Date: 10/15/2025
-- Description: Retrieves stadiums associated with a user.

CREATE PROCEDURE [dbo].[GetUserStadiums]
    @pEmail NVARCHAR(254)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @AccountId BIGINT;

    EXEC [dbo].[GetAccountIdByEmail]
        @pEmail,
        @AccountId OUTPUT;

    IF (@AccountId IS NULL OR @AccountId <= 0)
    BEGIN
        SELECT 101201 AS errorCode; -- ACCOUNT_NOT_FOUND
    END
    ELSE
    BEGIN
        ;WITH MyStadiums AS
        (
            SELECT TOP 100
                FS.StadiumId,
                CAST(1 AS BIT) AS IsMyStadium,
                FS.UpdatedAt
            FROM FootballStadiums FS
            INNER JOIN UserAccounts UA
                ON FS.ManagerAccountId = UA.AccountId
                AND UA.DeletedAt IS NULL
            WHERE UA.AccountId = @AccountId
              AND FS.DeletedAt IS NULL
            ORDER BY FS.UpdatedAt DESC
        ),
        Last5StadiumsOfMatchesCreated AS
        (
            SELECT DISTINCT TOP 5
                FM.StadiumId,
                CAST(0 AS BIT) AS IsMyStadium,
                FM.CreatedAt
            FROM FootballMatches FM
            LEFT JOIN MyStadiums MS
                ON MS.StadiumId = FM.StadiumId
            WHERE FM.AccountId = @AccountId
              AND FM.StadiumId IS NOT NULL
              AND FM.DeletedAt IS NULL
              AND MS.StadiumId IS NULL
            ORDER BY FM.CreatedAt DESC
        ),
        Last5StadiumsInOtherMatches AS
        (
            SELECT DISTINCT TOP 5
                FM.StadiumId,
                CAST(0 AS BIT) AS IsMyStadium,
                FM.CreatedAt
            FROM FootballMatches FM
            INNER JOIN FootballClubs FC
                ON FC.ClubId = FM.ClubId
                AND FC.DeletedAt IS NULL
            INNER JOIN ClubMembers CM
                ON CM.ClubId = FC.ClubId
                AND CM.DeletedAt IS NULL
            LEFT JOIN MyStadiums MS
                ON MS.StadiumId = FM.StadiumId
            LEFT JOIN Last5StadiumsOfMatchesCreated LSM
                ON LSM.StadiumId = FM.StadiumId
            WHERE CM.AccountId = @AccountId
              AND FM.StadiumId IS NOT NULL
              AND FM.DeletedAt IS NULL
              AND MS.StadiumId IS NULL
              AND LSM.StadiumId IS NULL
            ORDER BY FM.CreatedAt DESC
        ),
        StadiumsInLastClub AS
        (
            SELECT DISTINCT TOP 5
                FS.StadiumId,
                CAST(0 AS BIT) AS IsMyStadium,
                FC.CreatedAt
            FROM FootballStadiums FS
            INNER JOIN FootballClubs FC
                ON FS.LastClubId = FC.ClubId
                AND FC.DeletedAt IS NULL
            INNER JOIN ClubMembers CM
                ON CM.ClubId = FC.ClubId
                AND CM.DeletedAt IS NULL
            LEFT JOIN MyStadiums MS
                ON MS.StadiumId = FS.StadiumId
            LEFT JOIN Last5StadiumsInOtherMatches LSM
                ON LSM.StadiumId = FS.StadiumId
            LEFT JOIN Last5StadiumsOfMatchesCreated LSMC
                ON LSMC.StadiumId = FS.StadiumId
            WHERE CM.AccountId = @AccountId
              AND FS.StadiumId IS NOT NULL
              AND FS.DeletedAt IS NULL
              AND MS.StadiumId IS NULL
              AND LSM.StadiumId IS NULL
              AND LSMC.StadiumId IS NULL
            ORDER BY FC.CreatedAt DESC
        ),
        AllStadiums AS
        (
            SELECT StadiumId, IsMyStadium FROM MyStadiums
            UNION
            SELECT StadiumId, IsMyStadium FROM Last5StadiumsOfMatchesCreated
            UNION
            SELECT StadiumId, IsMyStadium FROM Last5StadiumsInOtherMatches
            UNION
            SELECT StadiumId, IsMyStadium FROM StadiumsInLastClub
        )
        SELECT DISTINCT
            FS.StadiumId,
            SN.Name AS StadiumName,
            SM.Name AS StadiumMake,
            FS.Capacity,
            FS.Address,
            ST.Name AS StadiumType,
            FS.UUID,
            MA.Url AS ImageUrl,
            C.Name AS CountryName,
            C.Code AS CountryCode,
            CT.Name AS CityName,
            FC.UUID AS ClubUUID,
            ASD.IsMyStadium,
            FS.UpdatedAt
        FROM FootballStadiums FS
        INNER JOIN AllStadiums ASD
            ON FS.StadiumId = ASD.StadiumId
        LEFT JOIN StadiumNames SN
            ON FS.StadiumNameId = SN.StadiumNameId
            AND SN.DeletedAt IS NULL
        LEFT JOIN StadiumMakes SM
            ON SM.StadiumMakeId = FS.StadiumMakeId
            AND SM.DeletedAt IS NULL
        LEFT JOIN StadiumTypes ST
            ON ST.StadiumTypeId = FS.StadiumTypeId
            AND ST.DeletedAt IS NULL
        LEFT JOIN StadiumImages SI
            ON SI.StadiumId = FS.StadiumId
            AND SI.DeletedAt IS NULL
        LEFT JOIN MediaAssets MA
            ON MA.MediaAssetId = SI.MediaAssetId
            AND MA.DeletedAt IS NULL
        LEFT JOIN Countries C
            ON C.CountryId = FS.CountryId
            AND C.DeletedAt IS NULL
        LEFT JOIN Cities CT
            ON CT.CityId = FS.CityId
            AND CT.DeletedAt IS NULL
        LEFT JOIN FootballClubs FC
            ON FS.LastClubId = FC.ClubId
            AND FC.DeletedAt IS NULL
        WHERE FS.DeletedAt IS NULL
        ORDER BY ASD.IsMyStadium DESC, FS.UpdatedAt DESC;
    END;
END;
RETURN 0;
GO


-- Author: ecamargo
-- Date: 10/15/2025
-- Description: Retrieves user contact information excluding email.

CREATE PROCEDURE [dbo].[GetUserContactInfo]
    @pEmail NVARCHAR(254)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @UserId BIGINT;

    EXEC [dbo].[GetUserIdByEmail]
        @pEmail,
        @UserId OUTPUT;

    IF (@UserId IS NULL OR @UserId <= 0)
    BEGIN
        SELECT 101000 AS errorCode; -- USER_NOT_FOUND
    END
    ELSE
    BEGIN
        SELECT
            CIT.Name,
            UCI.Value
        FROM ContactInfoTypes CIT
        LEFT JOIN UserContactInfo UCI
            ON UCI.ContactInfoTypeId = CIT.ContactInfoTypeId
            AND UCI.UserId = @UserId
            AND UCI.DeletedAt IS NULL
        LEFT JOIN UserProfiles UP
            ON UP.UserId = UCI.UserId
            AND CIT.DeletedAt IS NULL
        WHERE CIT.Name <> 'Email'
          AND UP.DeletedAt IS NULL;
    END;
END;
RETURN 0;
GO


-- Author: ecamargo
-- Date: 10/15/2025
-- Description: Retrieves available user roles.

CREATE PROCEDURE [dbo].[GetUserRoles]
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        Name,
        Description
    FROM ClubRoles
    WHERE DeletedAt IS NULL;
END;
RETURN 0;
GO
