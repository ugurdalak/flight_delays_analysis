--Updating cancellation_reason column with the values in cancellation_codes 
--to avoid join process to improve performance
UPDATE
	flights f
SET
	cancellation_reason = 'Airline/Carrier'
WHERE
	f.cancellation_reason = 'A';

UPDATE
	flights f
SET
	cancellation_reason = 'Weather'
WHERE
	f.cancellation_reason = 'B';

UPDATE
	flights f
SET
	cancellation_reason = 'National Air System'
WHERE
	f.cancellation_reason = 'C';

UPDATE
	flights f
SET
	cancellation_reason = 'Security'
WHERE
	f.cancellation_reason = 'D';

UPDATE
	flights f
SET
	cancellation_reason = 'No Cancellation'
WHERE
	f.cancellation_reason = '';
--Check Updates--
SELECT
	COUNT(*)
FROM
	flights
WHERE
	cancellation_reason IS NULL;
--1. Cascading Delay Control on High-Impact Routes
--We need to understand precisely where network failures cascade, indicating flaws in our scheduled aircraft turnarounds.
--•	Task: Identify the Top 5 routes (Origin-Destination pairs) based on total accumulated arrival delay in minutes.
--•	Deliverable: For these 5 routes, quantify the proportion of the total delay that is directly attributable to 
--Late Aircraft Delay (LAD).

SELECT
	CONCAT(origin_airport, '-', destination_airport) AS route,
	SUM(arrival_delay) AS total_arrival_delay,
	SUM(late_aircraft_delay) AS late_aircraft_delay,
	ROUND((SUM(late_aircraft_delay::NUMERIC )/ SUM(arrival_delay))* 100 , 1) AS lad_ratio
FROM
	flights
WHERE
	arrival_delay > 0
GROUP BY
	CONCAT(origin_airport, '-', destination_airport)
ORDER BY
	total_arrival_delay DESC
LIMIT 5;
----UA Operation Check----
SELECT
	CONCAT(origin_airport, '-', destination_airport) AS route,
	SUM(arrival_delay) AS total_arrival_delay,
	SUM(late_aircraft_delay) AS late_aircraft_delay,
	ROUND((SUM(late_aircraft_delay::NUMERIC )/ SUM(arrival_delay))* 100 , 1) AS lad_ratio
FROM
	flights
WHERE
	arrival_delay > 0
	AND airline = 'UA'
GROUP BY
	CONCAT(origin_airport, '-', destination_airport)
ORDER BY
	total_arrival_delay DESC
LIMIT 5;
--2. Cancellation Failure Rate Assessment
--We must quantify our internal failure rate and establish a decisive point for intervention to mitigate downstream costs.
--•	Task: Categorize cancellations based on the CANCELLATION_REASON field to isolate our Controllable factors 
--(Reason A: Airline/Carrier) versus External/Uncontrollable (Reasons B, C, D).
-

SELECT
	cancellation_reason,
	COUNT(*) AS cancellation_count,
	ROUND(COUNT(*)::NUMERIC /(SELECT COUNT(cancellation_reason) FROM flights WHERE airline = 'UA' AND cancellation_reason <> 'No Cancellation')* 100, 1) AS cancellation_rate
FROM
	flights
WHERE
	airline = 'UA'
	AND cancellation_reason <> 'No Cancellation'
GROUP BY
	cancellation_reason;
--Deliverable: Report the network-wide percentage of cancellations attributable to Controllable factors (Reason A).
SELECT
	COALESCE(airline, 'Sector'),
	SUM(CASE WHEN cancellation_reason = 'Airline/Carrier' THEN 1 ELSE 0 END) AS airline_cancelled,
	COUNT(*) AS planned_flight,
	ROUND((SUM(CASE WHEN cancellation_reason = 'Airline/Carrier' THEN 1 ELSE 0 END)::NUMERIC / COUNT(*))* 1000, 0) AS cont_cancel_in_1000_flights
FROM
	flights
GROUP BY
	CUBE(airline)
ORDER BY
	cont_cancel_in_1000_flights;
--Identifying controllable cancellations for UA across airports

SELECT
	COALESCE(origin_airport, 'UA Company'),
	COUNT(CASE WHEN cancellation_reason = 'Airline/Carrier' THEN 1 END) AS cancellation_count,
	COUNT(*) AS total_planned_flights,
	ROUND(COUNT(CASE WHEN cancellation_reason = 'Airline/Carrier' THEN 1 END) * 1000 / COUNT(*), 0) AS cont_cancel_in_1000_flights
FROM
	flights
WHERE
	airline = 'UA'
GROUP BY
	CUBE(origin_airport)
ORDER BY
	total_planned_flights DESC;
--- total minutes percentage for top 10--
WITH top10 AS 
(
SELECT
	COALESCE(origin_airport, 'UA Company'),
	COUNT(CASE WHEN cancellation_reason = 'Airline/Carrier' THEN 1 END) AS cancellation_count,
	COUNT(*) AS total_planned_flights,
	ROUND(COUNT(CASE WHEN cancellation_reason = 'Airline/Carrier' THEN 1 END) * 1000 / COUNT(*), 0) AS cont_cancel_in_1000_flights,
	RANK () OVER (
ORDER BY
	COUNT(*) DESC) AS rank_
FROM
	flights
WHERE
	airline = 'UA'
GROUP BY
	CUBE(origin_airport)
ORDER BY
	total_planned_flights DESC)
SELECT
	ROUND((SELECT SUM(total_planned_flights) 
FROM top10
WHERE rank_ BETWEEN 2 AND 11)/ SUM(total_planned_flights)* 100, 1)
FROM
	top10
WHERE
	rank_ = 1;

;
--- total count percentage for top 10--
WITH top10 AS 
(
SELECT
	COALESCE(origin_airport, 'UA Company'),
	COUNT(CASE WHEN cancellation_reason = 'Airline/Carrier' THEN 1 END) AS cancellation_count,
	COUNT(*) AS total_planned_flights,
	ROUND(COUNT(CASE WHEN cancellation_reason = 'Airline/Carrier' THEN 1 END) * 1000 / COUNT(*), 0) AS cont_cancel_in_1000_flights,
	RANK () OVER (
ORDER BY
	COUNT(*) DESC) AS rank_
FROM
	flights
WHERE
	airline = 'UA'
GROUP BY
	CUBE(origin_airport)
ORDER BY
	total_planned_flights DESC)
SELECT
	ROUND((SELECT SUM(cancellation_count) 
FROM top10
WHERE rank_ BETWEEN 2 AND 11)/ SUM(cancellation_count)* 100, 1)
FROM
	top10
WHERE
	rank_ = 1;

/*3. Morning Hub Congestion Strategy
We must pinpoint and address any systemic delays that jeopardize our early operations.
•	Task: Analyze the average Departure Delay distribution across all 24 hours of the day.*/

SELECT
	*
FROM
	flights;
--FOR SECTOR
SELECT
	ROUND(scheduled_departure::NUMERIC / 100, 0) AS departure_hour_block,
	ROUND(AVG(departure_delay), 0) AS avg_departure_delay
FROM
	flights
WHERE
	departure_delay > 0
GROUP BY
	departure_hour_block
ORDER BY
	avg_departure_delay DESC;
--FOR UA 
SELECT
	ROUND(scheduled_departure::NUMERIC / 100, 0) AS departure_hour_block,
	ROUND(AVG(departure_delay), 0) AS avg_departure_delay
FROM
	flights
WHERE
	airline = 'UA'
	AND departure_delay > 0
GROUP BY
	departure_hour_block
ORDER BY
	avg_departure_delay DESC;
--Deliverable: Identify the single one-hour time block that records the highest average departure delay, and specify that average delay (in minutes)

WITH delays_in_4AM AS (
SELECT
	airline,
	ROUND(scheduled_departure::NUMERIC / 100, 0) AS departure_hour_block,
	ROUND(AVG(departure_delay), 0) AS avg_departure_delay
FROM
	flights
WHERE
	departure_delay > 0
GROUP BY
	departure_hour_block,
	airline
ORDER BY
	avg_departure_delay DESC)

SELECT
	airline,
	avg_departure_delay
FROM
	delays_in_4AM
WHERE
	departure_hour_block = '4';
--4. Ground Crew Process Streamlining
--Inefficient ground movements waste fuel and time.
--•	Task: Identify the Top 5 Origin Airports that exhibit the longest average TAXI_OUT time across the entire dataset.

SELECT
	origin_airport,
	ROUND(AVG(taxi_out), 1) AS avg_taxiout
FROM
	flights
GROUP BY
	origin_airport
ORDER BY
	avg_taxiout DESC
LIMIT 5;
--•	Deliverable: Calculate the overall network median for TAXI_OUT time. Then, quantify the total estimated minutes of saving achievable at those 5 airports if they could match the calculated network median.
WITH network_median AS (
SELECT
	PERCENTILE_DISC(0.5) WITHIN GROUP (
ORDER BY
	taxi_out) AS median_taxi_out
FROM
	flights
)
SELECT
	f.origin_airport,
	ROUND(AVG(f.taxi_out), 1) AS avg_taxiout,
	COUNT(*) AS flight_count,
	m.median_taxi_out AS network_median,
	ROUND((AVG(f.taxi_out) - m.median_taxi_out) * COUNT(*), 0) AS total_minutes_savings
FROM
	flights f
CROSS JOIN network_median m
WHERE
	f.origin_airport IN (
	SELECT
		origin_airport
	FROM
		flights
	GROUP BY
		origin_airport
	ORDER BY
		AVG(taxi_out) DESC
	LIMIT 5
 )
	AND f.airline = 'UA'
GROUP BY
	f.origin_airport,
	m.median_taxi_out
ORDER BY
	total_minutes_savings DESC;
---- Data-check if there is any flight from 13502 for UA----
SELECT
	*
FROM
	flights
WHERE
	origin_airport = '13502'
	AND airline = 'UA';
