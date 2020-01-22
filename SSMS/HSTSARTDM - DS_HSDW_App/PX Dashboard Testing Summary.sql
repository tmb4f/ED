USE [DS_HSDW_App]
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER OFF
GO

--ALTER PROCEDURE [Rptg].[usp_Src_Dash_PatExp_ED_Test]
--AS
/**********************************************************************************************************************
WHAT: Stored procedure for Patient Experience Dashboard - Emergency Department
WHO : Chris Mitchell
WHEN: 5/18/2018
WHY : Produce surveys results for EMERGENCY DEPARTMENT patient experience dashboard
-----------------------------------------------------------------------------------------------------------------------
INFO: 
      INPUTS:	DS_HSDW_Prod.dbo.Fact_PressGaney_Responses
				DS_HSDW_Prod.rptg.Balanced_Scorecard_Mapping
				DS_HSDW_Prod.dbo.Dim_PG_Question
				DS_HSDW_Prod.dbo.Fact_Pt_Acct
				DS_HSDW_Prod.dbo.Dim_Pt
				DS_HSDW_Prod.dbo.Dim_Physcn
				DS_HSDW_Prod.dbo.Dim_Date
				DS_HSDW_App.Rptg.[PG_Extnd_Attr]
                  
      OUTPUTS:  ED Survey Results
   
------------------------------------------------------------------------------------------------------------------------
MODS: 	3/16/18 -- flag custom_question questions to remove them from mean calculations
        10/01/2019 -- TMB: changed logic that assigns targets to domains
***********************************************************************************************************************/

SET NOCOUNT ON

IF OBJECT_ID('tempdb..#er_resp ') IS NOT NULL
DROP TABLE #er_resp

IF OBJECT_ID('tempdb..#surveys_er ') IS NOT NULL
DROP TABLE #surveys_er

IF OBJECT_ID('tempdb..#surveys_er_sum ') IS NOT NULL
DROP TABLE #surveys_er_sum

IF OBJECT_ID('tempdb..#surveys_er2_sum ') IS NOT NULL
DROP TABLE #surveys_er2_sum

IF OBJECT_ID('tempdb..#surveys_er2 ') IS NOT NULL
DROP TABLE #surveys_er2

IF OBJECT_ID('tempdb..#surveys_er3 ') IS NOT NULL
DROP TABLE #surveys_er3

IF OBJECT_ID('tempdb..#ED ') IS NOT NULL
DROP TABLE #ED

DECLARE @currdate AS DATE;
DECLARE @startdate AS DATE;
DECLARE @enddate AS DATE;

    SET @currdate=CAST(GETDATE() AS DATE);

    IF @startdate IS NULL
        AND @enddate IS NULL
        BEGIN
            SET @startdate = CAST(DATEADD(MONTH,DATEDIFF(MONTH,0,DATEADD(MONTH,-24,GETDATE())),0) AS DATE); 
            SET @enddate= CAST(EOMONTH(GETDATE()) AS DATE); 
        END;

SELECT
	SURVEY_ID
	,sk_Dim_PG_Question
	,sk_Fact_Pt_Acct
	,sk_Dim_Pt
	,Svc_Cde
	,RECDATE
	,DISDATE
	,CAST(VALUE AS NVARCHAR(500)) AS VALUE
	,CASE WHEN sk_Dim_Clrt_DEPt = 0 THEN 378 ELSE sk_Dim_Clrt_DEPt END AS sk_Dim_Clrt_DEPt
	,sk_Dim_Physcn
INTO #er_resp
FROM DS_HSDW_Prod.Rptg.vwFact_PressGaney_Responses
WHERE sk_Dim_PG_Question IN
(
	'323','324','326','327','328','329','330','332','378','379','380','382','383','384','385','388',
	'389','396','397','398','399','400','401','429','431','433','434','435','436','437','440','441',
	'442','446','449','450','1212','1213','1214'
)

--SELECT *
--FROM #er_resp
--ORDER BY RECDATE
--       , SURVEY_ID

SELECT DISTINCT
	 Resp.SURVEY_ID
	,Resp.sk_Fact_Pt_Acct
	,Resp.RECDATE
	,Resp.DISDATE
	,ddte.Fyear_num AS REC_FY
	,phys.DisplayName AS Phys_Name
	,phys.DEPT AS Phys_Dept
	,phys.Division AS Phys_Div
	,Resp.sk_Dim_Clrt_DEPt
	,CAST(COALESCE(dept.DEPARTMENT_ID,'Unknown') AS VARCHAR(255)) AS Survey_Department_Id
	,dept.Clrt_DEPt_Nme AS Survey_Department_Name
	 ,loc_master.EPIC_DEPARTMENT_ID
	 ,loc_master.epic_department_name
	 ,loc_master.SERVICE_LINE_ID
	 ,CASE WHEN loc_master.opnl_service_name = 'Emergency Department' AND (loc_master.service_line IS NULL OR loc_master.SERVICE_LINE = 'Unknown') THEN 'Emergency Department'
		   WHEN loc_master.service_line IS NULL OR loc_master.service_line = 'Unknown' THEN 'Other'
		   ELSE loc_master.service_line END AS Survey_Service_Line
	 ,CASE WHEN loc_master.opnl_service_name = 'Emergency Department' AND (loc_master.service_line IS NULL OR loc_master.SERVICE_LINE = 'Unknown') THEN 'Emergency Department'
		   WHEN loc_master.service_line IS NULL OR loc_master.service_line = 'Unknown' THEN 'Other'
		   ELSE loc_master.service_line END AS SERVICE_LINE
	,'Emergency Department' AS UNIT
	,'Emergency Department' AS Survey_Unit
	,CAST(Resp.VALUE AS NVARCHAR(500)) AS VALUE -- prevents Tableau from erroring out on import data source
	,CASE WHEN Resp.VALUE IS NOT NULL THEN 1 ELSE 0 END AS VAL_COUNT
	,extd.DOMAIN
	,extd.DOMAIN AS Domain_Goals -- see line below
	--,CASE WHEN resp.sk_Dim_PG_Question = '7' THEN 'Quietness' WHEN Resp.sk_Dim_PG_Question = '6' THEN 'Cleanliness' ELSE DOMAIN END AS Domain_Goals is there an er equivalent of this?
	,CASE WHEN resp.sk_Dim_PG_Question <> '326' THEN -- Age
			CASE WHEN Resp.VALUE = '5' THEN 100
				WHEN Resp.VALUE = '4' THEN 75
				WHEN Resp.VALUE = '3' THEN 50
				WHEN Resp.VALUE = '2' THEN 25
				WHEN Resp.VALUE = '1' THEN 0
				ELSE CAST(Resp.VALUE AS NVARCHAR(500))
			END
	 END AS VALUE_Rptg -- Restated response to accomodate Press Ganey's translation of the 1-5 to 0-100 scale
	,CASE WHEN Resp.sk_Dim_PG_Question IN ('433','436','1213','1212','435','437','1214') THEN 1 ELSE 0 END AS custom_question -- these questions are not included in means
    ,CASE WHEN VALUE = 5 THEN 1 ELSE 0 END AS TOP_BOX
	,qstn.VARNAME
	,qstn.sk_Dim_PG_Question
	,extd.QUESTION_TEXT_ALIAS -- Short form of question text
	,CASE WHEN Resp_Age.AGE < 18 THEN 'Peds' WHEN Resp_Age.AGE >= 18 THEN 'Adult' ELSE NULL END AS AGE_STATUS
	,ddte.month_num
	,ddte.month_short_name
	INTO #surveys_er
    FROM #er_resp AS Resp
	--FROM DS_HSDW_Prod.Rptg.vwFact_PressGaney_Responses AS Resp
	INNER JOIN DS_HSDW_Prod.dbo.Dim_PG_Question AS qstn
		ON Resp.sk_Dim_PG_Question = qstn.sk_Dim_PG_Question
	INNER JOIN DS_HSDW_Prod.Rptg.vwDim_Date ddte
	    ON ddte.day_date = Resp.RECDATE
	LEFT OUTER JOIN DS_HSDW_Prod.dbo.Fact_Pt_Acct AS fpa -- LEFT OUTER, including -1 or survey counts won't match press ganey
		ON Resp.sk_Fact_Pt_Acct = fpa.sk_Fact_Pt_Acct
	LEFT OUTER JOIN DS_HSDW_Prod.dbo.Dim_Pt AS pat
		ON Resp.sk_Dim_Pt = pat.sk_Dim_Pt
	LEFT OUTER JOIN DS_HSDW_Prod.dbo.Dim_Physcn AS phys
		ON Resp.sk_Dim_Physcn = phys.sk_Dim_Physcn
	LEFT OUTER JOIN
	(
		SELECT SURVEY_ID, CAST(MAX(VALUE) AS NVARCHAR(500)) AS AGE FROM DS_HSDW_Prod.Rptg.vwFact_PressGaney_Responses
		WHERE sk_Dim_PG_Question = '326'-- Age question for ER
		--AND sk_Fact_Pt_Acct > 0  
		GROUP BY SURVEY_ID
	) Resp_Age
		ON Resp.SURVEY_ID = Resp_Age.SURVEY_ID 
	LEFT OUTER JOIN
	(
		SELECT DISTINCT sk_Dim_PG_Question, DOMAIN, QUESTION_TEXT_ALIAS FROM DS_HSDW_App.Rptg.PG_Extnd_Attr
	) extd
		ON RESP.sk_Dim_PG_Question = extd.sk_Dim_PG_Question
    LEFT OUTER JOIN DS_HSDW_Prod.Rptg.vwDim_Clrt_DEPt dept
	    ON Resp.sk_Dim_Clrt_DEPt = dept.sk_Dim_Clrt_DEPt
    LEFT OUTER JOIN DS_HSDW_Prod.Rptg.vwRef_MDM_Location_Master_EpicSvc AS loc_master
	    ON dept.DEPARTMENT_ID = loc_master.EPIC_DEPARTMENT_ID
	--WHERE  Resp.Svc_Cde='ER' AND qstn.sk_Dim_PG_Question IN
	--(
	--	'323','324','326','327','328','329','330','332','378','379','380','382','383','384','385','388',
	--	'389','396','397','398','399','400','401','429','431','433','434','435','436','437','440','441',
	--	'442','446','449','450','1212','1213','1214'
	--)

--SELECT *
----SELECT DISTINCT
----	REC_FY
----  , sk_Dim_Clrt_DEPt
--FROM #surveys_er
--WHERE REC_FY IN (2019,2020)
----AND sk_Dim_Clrt_DEPt = 0
--AND Domain_Goals IS NOT NULL
----ORDER BY REC_FY
----        ,AGE_STATUS
----        ,SURVEY_ID
----		,VARNAME
--ORDER BY REC_FY
--        ,SURVEY_ID
--		,Domain_Goals
--		,VARNAME

--SELECT   REC_FY
--       , month_num
--	   , month_short_name
--	   , AGE_STATUS
--       , Domain_Goals
--	   ,SUM(TOP_BOX) AS TOP_BOX
--	   ,SUM(VAL_COUNT) AS VAL_COUNT
--	   ,COUNT(*) AS N
--FROM #surveys_er
--WHERE Domain_Goals IS NOT NULL
--AND REC_FY IN (2019,2020)
--GROUP BY REC_FY
--       , month_num
--	   , month_short_name
--	   , AGE_STATUS
--       , Domain_Goals
--ORDER BY REC_FY
--       , month_num
--	   , month_short_name
--	   , AGE_STATUS
--       , Domain_Goals

SELECT *
FROM #surveys_er
WHERE DOMAIN = 'Arrival'
AND AGE_STATUS = 'Adult'
AND Survey_Department_Name = 'UVHE EMERGENCY DEPT'
AND REC_FY = 2020
ORDER BY REC_FY
       , month_num
	   , month_short_name
	   , VARNAME

SELECT  REC_FY
      , month_num
	  , month_short_name
	  , Survey_Department_Name
	  , DOMAIN
	  , AGE_STATUS
	  , VARNAME
	  , QUESTION_TEXT_ALIAS
	  ,SUM(TOP_BOX) AS TOP_BOX
	  ,SUM(VAL_COUNT) AS VAL_COUNT
	  ,COUNT(*) AS N
FROM #surveys_er
WHERE DOMAIN = 'Arrival'
AND AGE_STATUS = 'Adult'
AND Survey_Department_Name = 'UVHE EMERGENCY DEPT'
AND REC_FY = 2020
GROUP BY REC_FY
      , month_num
	  , month_short_name
	  , Survey_Department_Name
	  , DOMAIN
	  , AGE_STATUS
	  , VARNAME
	  , QUESTION_TEXT_ALIAS
ORDER BY REC_FY
      , month_num
	  , month_short_name
	  , Survey_Department_Name
	  , DOMAIN
	  , AGE_STATUS
	  , VARNAME
	  , QUESTION_TEXT_ALIAS

SELECT DISTINCT
	SURVEY_ID
FROM #surveys_er
WHERE DOMAIN = 'Arrival'
AND AGE_STATUS = 'Adult'
AND Survey_Department_Name = 'UVHE EMERGENCY DEPT'
AND REC_FY = 2020
AND month_num = 7

/*

------------------------------------------------------------------------------------------
--- GENERATE SUMMARY FOR TESTING

------------------------------------------------------------------------------------------

----SELECT DISTINCT
--SELECT
--	REC_FY,
--	month_num,
--	month_short_name,
--    resp.Survey_Unit,
--    Survey_Service_Line,
--	SERVICE_LINE_ID,
--    SERVICE_LINE,
--    UNIT,
--    Survey_Department_Id,
--    Survey_Department_Name,
--    EPIC_DEPARTMENT_ID,
--    epic_department_name,
--	AGE_STATUS,
--    DOMAIN,
--    Domain_Goals,
--    VALUE,
--	TOP_BOX,
--    VAL_COUNT
----INTO #surveys_op_sum
--FROM #surveys_er resp
----WHERE REC_FY = 2020
--WHERE REC_FY IN (2019,2020)
----AND sk_Dim_PG_Question = 803 -- Rate Provider 0-10
--AND Domain_Goals IS NOT NULL
----AND (Domain_Goals IS NOT NULL
----AND Domain_Goals <> 'Additional Questions About Your Care')
--ORDER BY resp.REC_FY
--       , resp.month_num
--	   , resp.month_short_name
--	   , resp.Survey_Service_Line
--	   , resp.Survey_Department_Id
--	   , resp.Survey_Department_Name
--	   , resp.SERVICE_LINE
--	   , resp.EPIC_DEPARTMENT_ID
--	   , resp.epic_department_name
--	   , resp.AGE_STATUS
--	   , resp.Domain_Goals

SELECT resp.REC_FY,
       resp.month_num,
       resp.month_short_name,
       resp.Survey_Unit,
       resp.Survey_Service_Line,
       resp.Survey_Department_Id,
       resp.Survey_Department_Name,
       resp.UNIT,
       resp.SERVICE_LINE_ID,
       resp.SERVICE_LINE,
       resp.EPIC_DEPARTMENT_ID,
       resp.epic_department_name,
	   resp.AGE_STATUS,
       resp.Domain_Goals,
       SUM(resp.TOP_BOX) AS TOP_BOX,
       SUM(resp.VAL_COUNT) AS VAL_COUNT,
	   CAST(CAST(SUM(resp.TOP_BOX) AS NUMERIC(6,3)) / CAST(SUM(resp.VAL_COUNT) AS NUMERIC(6,3)) AS NUMERIC(4,3)) AS SCORE,
	   COUNT(*) AS N
INTO #surveys_er_sum
FROM
(
--SELECT DISTINCT
SELECT
	REC_FY,
	month_num,
	month_short_name,
    Survey_Unit,
    Survey_Service_Line,
    Survey_Department_Id,
    Survey_Department_Name,
    UNIT,
	SERVICE_LINE_ID,
    SERVICE_LINE,
    EPIC_DEPARTMENT_ID,
    epic_department_name,
	AGE_STATUS,
    Domain_Goals,
	TOP_BOX,
    VAL_COUNT
--INTO #surveys_op_sum
FROM #surveys_er
--WHERE REC_FY = 2020
WHERE REC_FY IN (2019,2020)
--AND sk_Dim_PG_Question = 17 -- Rate Hospital 0-10
AND Domain_Goals IS NOT NULL
--AND (Domain_Goals IS NOT NULL
--AND Domain_Goals NOT IN
--(
--'Access to Specialists'
--,'Additional Questions About Your Care'
--,'Between Visit Communication'
--,'Health Promotion and Education'
--,'Education About Medication'
--,'Shared Decision Making'
--,'Stewardship of Patient Resources'
--))
) resp
GROUP BY 
	REC_FY,
	month_num,
	month_short_name,
    Survey_Unit,
    Survey_Service_Line,
    Survey_Department_Id,
    Survey_Department_Name,
    UNIT,
	SERVICE_LINE_ID,
    SERVICE_LINE,
    EPIC_DEPARTMENT_ID,
    epic_department_name,
	AGE_STATUS,
	Domain_Goals

--SELECT
--       REC_FY,
--       month_num,
--       month_short_name,
--       Survey_Unit,
--       Survey_Service_Line,
--       Survey_Department_Id,
--       Survey_Department_Name,
--       UNIT,
--       SERVICE_LINE_ID,
--       SERVICE_LINE,
--       EPIC_DEPARTMENT_ID,
--       epic_department_name,
--	   AGE_STATUS,
--	   Domain_Goals,
--       TOP_BOX,
--       VAL_COUNT,
--	   SCORE,
--	   N
--FROM #surveys_er_sum
--ORDER BY REC_FY
--       , month_num
--	   , month_short_name
--	   , Survey_Unit
--	   , Survey_Service_Line
--	   , Survey_Department_Id
--	   , Survey_Department_Name
--	   , UNIT
--	   , SERVICE_LINE_ID
--	   , SERVICE_LINE
--	   , EPIC_DEPARTMENT_ID
--	   , epic_department_name
--	   , AGE_STATUS
--	   , Domain_Goals

------------------------------------------------------------------------------------------
--- JOIN TO DIM_DATE

 SELECT
	'Emergency Department' AS Event_Type
	,rec.Fyear_num AS Event_FY
	,surveys_er_sum.Survey_Unit
	,surveys_er_sum.Survey_Service_Line
	,surveys_er_sum.Survey_Department_Id
	,surveys_er_sum.Survey_Department_Name
	,surveys_er_sum.UNIT
	,surveys_er_sum.SERVICE_LINE_ID
	,surveys_er_sum.SERVICE_LINE
	,surveys_er_sum.EPIC_DEPARTMENT_ID
	,surveys_er_sum.epic_department_name
	,surveys_er_sum.AGE_STATUS
	,surveys_er_sum.Domain_Goals
	,surveys_er_sum.month_num
	,surveys_er_sum.month_short_name
	,surveys_er_sum.TOP_BOX
	,surveys_er_sum.VAL_COUNT
	,surveys_er_sum.SCORE
	,surveys_er_sum.N
	,surveys_er_goals.GOAL
INTO #surveys_er2_sum
FROM #surveys_er_sum surveys_er_sum
LEFT OUTER JOIN
(
SELECT DISTINCT
	GOAL_FISCAL_YR,
    SERVICE_LINE,
    UNIT,
    EPIC_DEPARTMENT_ID,
    EPIC_DEPARTMENT_NAME,
    DOMAIN,
	AGE_STATUS,
    GOAL
FROM DS_HSDW_App.Rptg.ED_Goals_Test
) surveys_er_goals
ON surveys_er_sum.REC_FY = surveys_er_goals.GOAL_FISCAL_YR AND surveys_er_sum.AGE_STATUS = surveys_er_goals.AGE_STATUS AND surveys_er_sum.Domain_Goals = surveys_er_goals.DOMAIN
INNER JOIN
(
SELECT DISTINCT
	Fyear_num
FROM DS_HSDW_Prod.dbo.Dim_Date
WHERE day_date >= @startdate AND day_date <= @enddate
) rec
ON rec.Fyear_num = surveys_er_sum.REC_FY
--ORDER BY Event_Date, SURVEY_ID, sk_Dim_PG_Question

SELECT Event_Type,
       Event_FY,
       Survey_Unit,
       Survey_Service_Line,
       Survey_Department_Id,
       Survey_Department_Name,
       UNIT,
	   SERVICE_LINE_ID,
       SERVICE_LINE,
       EPIC_DEPARTMENT_ID,
       epic_department_name,
	   AGE_STATUS,
       Domain_Goals,
       month_num,
       month_short_name,
       TOP_BOX,
       VAL_COUNT,
       SCORE,
       N,
       GOAL
FROM #surveys_er2_sum
ORDER BY Event_FY
	   , Survey_Unit
	   , Survey_Service_Line
	   , Survey_Department_Id
	   , Survey_Department_Name
	   , Domain_Goals
	   , AGE_STATUS
	   , UNIT
	   , SERVICE_LINE_ID
       , SERVICE_LINE
	   , EPIC_DEPARTMENT_ID
	   , epic_department_name
       , month_num
	   , month_short_name
*/
/*
------------------------------------------------------------------------------------------------------------------------------------

SELECT * INTO #surveys_er3
FROM #surveys_er2
UNION ALL

(
	SELECT
		 all_age.Event_Type
		,all_age.SURVEY_ID
		,all_age.sk_Fact_Pt_Acct
		,all_age.Event_Date
		,all_age.Event_Date_Disch
		,all_age.Event_FY
		,all_age.sk_Dim_PG_Question
		,all_age.VARNAME
		,all_age.QUESTION_TEXT_ALIAS
		,all_age.DOMAIN
		,all_age.Domain_Goals
		,all_age.Recvd_Date
		,all_age.Discharge_Date
		,all_age.Phys_Name
		,all_age.Phys_Dept
		,all_age.Phys_Div
		,goals.GOAL
		,goals_overall.GOAL AS GOAL_OVERALL
		,all_age.UNIT
		,all_age.VALUE
		,all_age.VALUE_Rptg
		,all_age.custom_question
		,all_age.TOP_BOX
		,all_age.VAL_COUNT
		,all_age.AGE_STATUS
	FROM
	(
		SELECT
			'Emergency Department' AS Event_Type
			,SURVEY_ID
			,sk_Fact_Pt_Acct
			,rec.day_date AS Event_Date
			,dis.day_date AS Event_Date_Disch
	        ,rec.Fyear_num AS Event_FY
			,sk_Dim_PG_Question
			,VARNAME
			,QUESTION_TEXT_ALIAS
			,#surveys_er.Domain
			,Domain_Goals
			,RECDATE AS Recvd_Date
			,DISDATE AS Discharge_Date
			,REC_FY
			,Phys_Name
			,Phys_Dept
			,Phys_Div
			,#surveys_er.UNIT
			,VALUE
			,VALUE_Rptg
			,custom_question
			,TOP_BOX
			,VAL_COUNT
			,CASE WHEN SURVEY_ID IS NULL THEN NULL ELSE 'All' END AS AGE_STATUS
		FROM (SELECT * FROM DS_HSDW_Prod.dbo.Dim_Date WHERE day_date >= @startdate AND day_date <= @enddate) rec
		LEFT OUTER JOIN #surveys_er
		ON rec.day_date = #surveys_er.RECDATE
		FULL OUTER JOIN (SELECT * FROM DS_HSDW_Prod.dbo.Dim_Date WHERE day_date >= @startdate AND day_date <= @enddate) dis -- Need to report by both the discharge date on the survey as well as the received date of the survey
		ON dis.day_date = #surveys_er.DISDATE
		LEFT OUTER JOIN DS_HSDW_App.Rptg.ED_Goals_Test goals
		ON #surveys_er.REC_FY = goals.GOAL_FISCAL_YR AND #surveys_er.AGE_STATUS = goals.AGE_STATUS AND #surveys_er.Domain_Goals = goals.DOMAIN
	) all_age
	LEFT OUTER JOIN DS_HSDW_App.Rptg.ED_Goals_Test goals
	ON all_age.REC_FY = goals.GOAL_FISCAL_YR AND all_age.AGE_STATUS = goals.AGE_STATUS AND all_age.Domain_Goals = goals.DOMAIN
	LEFT OUTER JOIN
	DS_HSDW_App.Rptg.ED_Goals_Test goals_overall
	ON goals_overall.GOAL_FISCAL_YR = all_age.REC_FY AND goals_overall.AGE_STATUS = all_age.AGE_STATUS AND goals_overall.DOMAIN = 'Overall Mean' AND goals_overall.AGE_STATUS = 'All'
)

-------------------------------------------------------------------------------------------------------------------------------------
-- RESULTS


 SELECT
    [Event_Type]
   ,[SURVEY_ID]
   ,[sk_Fact_Pt_Acct]
   ,[Event_Date]
   ,[Event_Date_Disch]
   ,Event_FY
   ,[sk_Dim_PG_Question]
   ,[VARNAME]
   ,[QUESTION_TEXT_ALIAS]
   ,[DOMAIN]
   ,[Domain_Goals]
   ,[Recvd_Date]
   ,[Discharge_Date]
   ,[Phys_Name]
   ,[Phys_Dept]
   ,[Phys_Div]
   ,[GOAL]
   ,[GOAL_OVERALL]
   ,[UNIT]
   ,[VALUE]
   ,[VALUE_Rptg]
   ,[custom_question]
   ,TOP_BOX
   ,[VAL_COUNT]
   ,AGE_STATUS
  FROM [#surveys_er3]
----------------------------------------------------------------------------------------------------------------------------
*/
GO


