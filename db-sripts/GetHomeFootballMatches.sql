
-- Author: ecamargo
-- Date: 10/10/2025
-- Description: Retrieves completed football matches for the Colombian football platform.

CREATE PROCEDURE [dbo].[GetHomeFootballMatches]
    @pUserEmail NVARCHAR(254) = NULL,
    @pStartDate DATETIME = NULL,
    @pEndDate DATETIME = NULL,
    @pOffset INT = 0,
    @pLimit INT = 10
AS
BEGIN
    SET NOCOUNT ON;

    -- Normalize date boundaries to include the complete requested days.
    DECLARE @FromDate DATETIME =
        CONVERT(
            DATETIME,
            CONVERT(VARCHAR(11), @pStartDate, 111) + ' 00:00:00',
            111
        );

    DECLARE @ToDate DATETIME =
        CONVERT(
            DATETIME,
            CONVERT(VARCHAR(11), @pEndDate, 111) + ' 23:59:59',
            111
        );

    ;WITH FootballMatches AS
    (
        SELECT
            FM.MatchId,
            FM.ClubId
        FROM FootballMatches FM
        INNER JOIN MatchStatuses MS
            ON FM.MatchStatusId = MS.MatchStatusId
            AND MS.DeletedAt IS NULL
        WHERE
            MS.Name = 'Finished'
            AND FM.DeletedAt IS NULL
            AND (FM.IsArchived = 0 OR FM.IsArchived IS NULL)
            AND FM.MatchVisibilityId = 1
            AND
            (
                (
                    @pStartDate IS NOT NULL
                    AND @pEndDate IS NOT NULL
                    AND CONVERT(DATETIME, FM.EndDateTime)
                        BETWEEN @FromDate AND @ToDate
                )
                OR
                (
                    @pStartDate IS NOT NULL
                    AND @pEndDate IS NULL
                    AND CONVERT(DATETIME, FM.EndDateTime) >= @FromDate
                )
                OR
                (
                    @pStartDate IS NULL
                    AND @pEndDate IS NOT NULL
                    AND CONVERT(DATETIME, FM.EndDateTime) <= @ToDate
                )
                OR
                (
                    @pStartDate IS NULL
                    AND @pEndDate IS NULL
                )
            )
        GROUP BY
            FM.MatchId,
            FM.ClubId,
            FM.CreatedAt
        ORDER BY
            FM.CreatedAt DESC
        OFFSET @pLimit * @pOffset ROWS
        FETCH NEXT @pLimit ROWS ONLY
    ),

    MatchesWithCoach AS
    (
        SELECT
            FM.MatchId,
            UP.UserId AS MatchCoachId,
            UP.FirstName AS MatchCoachFirstName,
            UP.LastName AS MatchCoachLastName,
            C.Code AS MatchCoachCountry,
            MA.Url AS MatchCoachProfileUrl,
            CR.Name AS MatchCoachRole
        FROM FootballMatches FM
        INNER JOIN FootballClubs FC
            ON FC.ClubId = FM.ClubId
            AND FC.DeletedAt IS NULL
        LEFT JOIN ClubMembers CM
            ON CM.ClubId = FC.ClubId
            AND CM.DeletedAt IS NULL
        LEFT JOIN ClubRoles CR
            ON CR.ClubRoleId = CM.ClubRoleId
            AND CR.DeletedAt IS NULL
        LEFT JOIN UserAccounts UA
            ON UA.AccountId = CM.AccountId
            AND UA.DeletedAt IS NULL
        LEFT JOIN UserProfiles UP
            ON UP.UserId = UA.UserId
            AND UP.DeletedAt IS NULL
        LEFT JOIN Countries C
            ON C.CountryId = UP.NationalityId
        LEFT JOIN UserProfileImages UPI
            ON UPI.AccountId = UA.AccountId
            AND UPI.DeletedAt IS NULL
            AND UPI.IsPrimary = 1
        LEFT JOIN MediaAssets MA
            ON MA.MediaAssetId = UPI.MediaAssetId
            AND MA.DeletedAt IS NULL
        WHERE
            CR.Name = 'Coach'
    )

    SELECT
        FM.UUID,

        CONVERT(VARCHAR, FM.KickoffDateTime, 120) AS KickoffDateTime,
        CONVERT(VARCHAR, FM.EndDateTime, 120) AS EndDateTime,

        CASE
            WHEN DATEDIFF(MINUTE, FM.KickoffDateTime, FM.EndDateTime) < 1
                THEN '< 1 min'

            WHEN DATEDIFF(MINUTE, FM.KickoffDateTime, FM.EndDateTime) = 1
                THEN '1 min'

            WHEN DATEDIFF(HOUR, FM.KickoffDateTime, FM.EndDateTime) < 1
                THEN CAST(
                    DATEDIFF(MINUTE, FM.KickoffDateTime, FM.EndDateTime)
                    AS NVARCHAR(50)
                ) + ' min'

            WHEN DATEDIFF(DAY, FM.KickoffDateTime, FM.EndDateTime) < 1
                THEN CAST(
                    DATEDIFF(HOUR, FM.KickoffDateTime, FM.EndDateTime)
                    AS NVARCHAR(50)
                ) + ' h ' +
                CAST(
                    DATEDIFF(MINUTE, FM.KickoffDateTime, FM.EndDateTime) % 60
                    AS NVARCHAR(50)
                ) + ' min'

            ELSE CAST(
                DATEDIFF(DAY, FM.KickoffDateTime, FM.EndDateTime)
                AS NVARCHAR(50)
            ) + ' days'
        END AS MatchDuration,

        AR.Name AS OwnerRole,
        OP.FirstName AS OwnerFirstName,
        OP.LastName AS OwnerLastName,
        OC.Code AS OwnerCountry,
        OMA.Url AS OwnerProfileImageUrl,
        OP.UserId AS OwnerUserId,

        MWC.MatchCoachId,
        MWC.MatchCoachFirstName,
        MWC.MatchCoachLastName,
        MWC.MatchCoachCountry,
        MWC.MatchCoachProfileUrl,
        MWC.MatchCoachRole,

        FS.StadiumId,
        SN.Name AS StadiumName,
        SMA.Url AS StadiumImageUrl,
        SC.Code AS StadiumCountry,

        MS2.HomeGoals,
        MS2.AwayGoals,
        MS2.ShotsOnTarget,
        MS2.YellowCards,
        MS2.MatchRating,

        CC.Name AS CompetitionCategory,

        FM.Comments AS TotalComments,
        FM.IsArchived AS IsArchived,
        FM.Votes AS TotalVotes,

        IIF(OA.Email = @pUserEmail, 1, 0) AS CanEdit,

        IIF(TM.TournamentMatchId IS NOT NULL, 1, 0)
            AS IsTournamentMatch

    FROM FootballMatches FM

    INNER JOIN FootballMatches FM2
        ON FM2.MatchId = FM.MatchId

    INNER JOIN MatchStatistics MS2
        ON MS2.MatchId = FM.MatchId

    INNER JOIN UserAccounts OA
        ON OA.AccountId = FM.AccountId
        AND OA.DeletedAt IS NULL

    INNER JOIN ClubRoles AR
        ON AR.ClubRoleId = OA.ClubRoleId

    LEFT JOIN UserProfiles OP
        ON OP.UserId = OA.UserId

    LEFT JOIN Countries OC
        ON OC.CountryId = OP.NationalityId

    LEFT JOIN UserProfileImages OPI
        ON OPI.AccountId = OA.AccountId
        AND OPI.DeletedAt IS NULL
        AND OPI.IsPrimary = 1

    LEFT JOIN MediaAssets OMA
        ON OMA.MediaAssetId = OPI.MediaAssetId

    LEFT JOIN MatchesWithCoach MWC
        ON MWC.MatchId = FM.MatchId

    LEFT JOIN CompetitionCategories CC
        ON CC.CompetitionCategoryId = FM.CompetitionCategoryId

    LEFT JOIN FootballStadiums FS
        ON FS.StadiumId = FM.StadiumId

    LEFT JOIN StadiumImages SI
        ON SI.StadiumId = FS.StadiumId
        AND SI.DeletedAt IS NULL
        AND SI.IsPrimary = 1

    LEFT JOIN MediaAssets SMA
        ON SMA.MediaAssetId = SI.MediaAssetId
        AND SMA.DeletedAt IS NULL

    LEFT JOIN StadiumNames SN
        ON SN.StadiumNameId = FS.StadiumNameId

    LEFT JOIN Countries SC
        ON SC.CountryId = FS.CountryId

    LEFT JOIN TournamentMatches TM
        ON TM.MatchId = FM.MatchId
        AND TM.DeletedAt IS NULL

    WHERE
        FM.IsArchived = 0
        OR FM.IsArchived IS NULL

    GROUP BY
        FM.UUID,
        FM.KickoffDateTime,
        FM.EndDateTime,
        AR.Name,
        OP.FirstName,
        OP.LastName,
        OC.Code,
        OMA.Url,
        OP.UserId,

        MWC.MatchCoachId,
        MWC.MatchCoachFirstName,
        MWC.MatchCoachLastName,
        MWC.MatchCoachCountry,
        MWC.MatchCoachProfileUrl,
        MWC.MatchCoachRole,

        FS.StadiumId,
        SN.Name,
        SMA.Url,
        SC.Code,

        MS2.HomeGoals,
        MS2.AwayGoals,
        MS2.ShotsOnTarget,
        MS2.YellowCards,
        MS2.MatchRating,

        CC.Name,
        FM.Comments,
        FM.IsArchived,
        FM.Votes,

        IIF(OA.Email = @pUserEmail, 1, 0),
        IIF(TM.TournamentMatchId IS NOT NULL, 1, 0)

    ORDER BY
        FM.EndDateTime DESC;

END;
