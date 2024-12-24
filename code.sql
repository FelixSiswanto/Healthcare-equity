
																
																					--1. Geographical coverage of healthcare
																				--A.Low coverage ratio per area

WITH Geocoverage AS (SELECT 
	Id,
    City,
	County,
    First,
    Last,
    Healthcare_expenses / 
    CASE 
        WHEN Healthcare_coverage IS NOT NULL AND Healthcare_coverage > 0 
        THEN Healthcare_coverage 
        ELSE 1 
    END AS Coverage_ratio
FROM Patients)

SELECT

    City,
	County,
    COUNT(CASE WHEN Coverage_ratio < 0.5 THEN Id ELSE NULL END) AS Low_Coverage_Count,
    COUNT(Id) AS Total_Count,
    ROUND(CAST(COUNT(CASE WHEN Coverage_ratio < 0.5 THEN Id ELSE NULL END) AS FLOAT) / COUNT(Id),2) AS Low_Coverage_Percentage
FROM Geocoverage
GROUP BY City,County
HAVING ROUND(CAST(COUNT(CASE WHEN Coverage_ratio < 0.5 THEN Id ELSE NULL END) AS FLOAT) / COUNT(Id),2) > 0.5;

                                                                                       --B. Underinsured ratio 
																					   
 --Based on https://www.who.int/data/gho/data/indicators/indicator-details/GHO/population-with-household-expenditures-on-health-greater-than-10-of-total-household-expenditure-or-income-(sdg-3-8-2)-(-) 10% is worrying

WITH Catastrophic_spending AS (SELECT
	City,
    Patient,
    Income,
    SUM(Healthcare_expenses) - SUM(Healthcare_coverage) AS Total_Healthcare_Expenditure,
    CASE 
        WHEN SUM(Healthcare_expenses) - SUM(Healthcare_coverage) > Income * 0.1 THEN 'Difficult'
        WHEN SUM(Healthcare_expenses) - SUM(Healthcare_coverage) > Income * 0.25 THEN 'Catastrophic'
        ELSE 'Below Threshold'
    END AS Income_expenditure_status
FROM Patients P
JOIN Encounter E ON P.Id = E.Patient
GROUP BY City,Patient, Income)

SELECT 
City,
COUNT(Patient) AS Total_patient,
COUNT(CASE WHEN Income_expenditure_status = 'Difficult' OR Income_expenditure_status = 'Catastrophic' THEN Patient ELSE NULL END) AS Underinsured,
ROUND(CAST(COUNT(CASE WHEN Income_expenditure_status = 'Difficult' OR Income_expenditure_status = 'Catastrophic' THEN Patient ELSE NULL END) AS FLOAT) / COUNT(Patient), 2) AS Underinsured_ratio
FROM Catastrophic_spending
GROUP BY City

																			--C. High patient load area 

SELECT 
    City,
	County,
    COUNT(DISTINCT Provider) AS Total_Providers,
    COUNT(*) AS Total_Patient_Visits,
    ROUND(COUNT(*) / COUNT(DISTINCT Provider), 2) AS Avg_Patient_Load_Per_Provider
FROM Encounter E
JOIN Patients P ON E.Patient = P.Id
GROUP BY City,County
HAVING COUNT(DISTINCT Provider) < 10	

																					--2.  Health disparity index accross race


WITH normalized_data AS (
SELECT 
      RACE, 
     (HEALTHCARE_EXPENSES - MIN(HEALTHCARE_EXPENSES) OVER ()) / 
      (MAX(HEALTHCARE_EXPENSES) OVER () - MIN(HEALTHCARE_EXPENSES) OVER ()) AS Norm_Expenses,
      (HEALTHCARE_COVERAGE - MIN(HEALTHCARE_COVERAGE) OVER ()) / 
      (MAX(HEALTHCARE_COVERAGE) OVER () - MIN(HEALTHCARE_COVERAGE) OVER ()) AS Norm_Coverage,
      (INCOME - MIN(INCOME) OVER ()) / 
     (MAX(INCOME) OVER () - MIN(INCOME) OVER ()) AS Norm_Income
FROM patients
)
SELECT 
    RACE, 
    AVG(Norm_Expenses) * 0.5 + AVG(Norm_Coverage) * 0.3 + AVG(Norm_Income) * 0.2 AS Health_Disparity_Index
FROM normalized_data
GROUP BY RACE

																			-- Extra 
--- Compensating providers (healthcare proffesionals) by finding who are the most commonly cited providers. 

---  who are the most common providers for these most frequently diagnosed diseases?
WITH common_conditions AS (
    SELECT TOP 10 
        Description AS common,
        COUNT(DISTINCT Encounter) AS encounter_count
    FROM Conditions
    GROUP BY Description
    
),
top10table AS (
    SELECT
        C.Encounter AS Encounter,
        C.Description AS Description
    FROM dbo.Conditions C
    INNER JOIN common_conditions cc
        ON C.Description = cc.common
),
providertable AS (
SELECT
    E.Provider,
    tt.Description,
	COUNT(DISTINCT tt.Encounter) AS Encounter_provided
FROM top10table tt
LEFT JOIN dbo.Encounter E
    ON tt.Encounter = E.Id
GROUP BY E.Provider,tt.Description)
,
Rankedprovider AS (
SELECT
	Provider,
	Description,
	Encounter_provided,
	RANK()OVER(PARTITION BY Description ORDER BY Encounter_provided DESC) AS Ranking
FROM providertable
)

SELECT
	Provider,
	Description,
	Encounter_provided,
	Ranking
FROM Rankedprovider
WHERE Ranking < 4 AND Provider IS NOT NULL
