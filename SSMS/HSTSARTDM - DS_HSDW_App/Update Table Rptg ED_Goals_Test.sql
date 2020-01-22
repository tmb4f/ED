USE DS_HSDW_App

UPDATE Rptg.ED_Goals_Test
SET DOMAIN = 'Overall Mean'
WHERE DOMAIN = 'Overall Assessment'
AND (GOAL IN (0.863,0.865,0.880))

UPDATE Rptg.ED_Goals_Test
SET DOMAIN = 'Overall Assessment'
WHERE DOMAIN = 'Overall Mean'
AND (GOAL IN (0.824,0.828,0.859))