-- =====================================================================
-- CONSIGNA 3 - METODOLOGIA HEFESTO
-- Modelo lógico DW: fact_rendimiento_piloto_session 
-- =====================================================================

CREATE DATABASE IF NOT EXISTS dw_rendimiento_piloto
    DEFAULT CHARACTER SET utf8mb4
    DEFAULT COLLATE utf8mb4_0900_ai_ci;

USE dw_rendimiento_piloto;

-- ---------------------------------------------------------------------
-- DIMENSIONES
-- ---------------------------------------------------------------------
drop table if exists dim_date;
drop table if exists dim_meeting;
drop table if exists dim_session;
drop table if exists dim_driver;
drop table if exists fact_rendimiento_piloto_session;

CREATE TABLE dim_date (
    date_key    INT  NOT NULL,
    full_date   DATE not null,
    `day`       INT  not null,
    `month`     INT  not null,
    `year`      INT  not null,
    PRIMARY KEY (date_key)
);

CREATE TABLE dim_meeting (
    meeting_key         INT          NOT NULL AUTO_INCREMENT,
    source_meeting_key  INT          NOT NULL,
    circuit_key         INT          NOT NULL,
    circuit_short_name  VARCHAR(100) NOT NULL,
    circuit_type        VARCHAR(50)  NULL,
    country_name        VARCHAR(100) NOT NULL,
    location            VARCHAR(150) NOT NULL,
    PRIMARY KEY (meeting_key),
    UNIQUE KEY uq_dim_meeting_source (source_meeting_key)
) ;

CREATE TABLE dim_session (
    session_key         INT          NOT NULL AUTO_INCREMENT,
    source_session_key  INT          NOT NULL,
    session_name        VARCHAR(100) NOT NULL,
    session_type        VARCHAR(50)  NOT NULL,
    is_cancelled        BOOLEAN      NOT NULL DEFAULT FALSE,
    PRIMARY KEY (session_key),
    UNIQUE KEY uq_dim_session_source (source_session_key)
) ;

CREATE TABLE dim_driver (
    driver_key     INT          NOT NULL AUTO_INCREMENT,
    driver_number  INT          NOT NULL,
    full_name      VARCHAR(150) NOT NULL ,
    team_name      VARCHAR(100) NOT NULL ,
    PRIMARY KEY (driver_key),
	UNIQUE KEY uq_dim_driver (driver_number, full_name, team_name) -- combinación unica de las tres columnas
) ;
 
-- ---------------------------------------------------------------------
-- TABLA DE HECHOS
-- Granularidad: una fila por piloto, por sesión, por meeting y por fecha
-- ---------------------------------------------------------------------

CREATE TABLE fact_rendimiento_piloto_session (
    date_key            INT           NOT NULL,
    meeting_key         INT           NOT NULL,
    session_key         INT           NOT NULL,
    driver_key          INT           NOT NULL,
    cantidad_vueltas    INT           NOT NULL,
    velocidad_media     DECIMAL(8,3)  NULL,
    lap_duration_medio  DECIMAL(10,3) NULL,
    cantidad_salidas_pit INT NOT NULL DEFAULT 0,
    PRIMARY KEY (date_key, meeting_key, session_key, driver_key),
    CONSTRAINT fk_fact_date
        FOREIGN KEY (date_key)    REFERENCES dim_date (date_key),
    CONSTRAINT fk_fact_meeting
        FOREIGN KEY (meeting_key) REFERENCES dim_meeting (meeting_key),
    CONSTRAINT fk_fact_session
        FOREIGN KEY (session_key) REFERENCES dim_session (session_key),
    CONSTRAINT fk_fact_driver
        FOREIGN KEY (driver_key)  REFERENCES dim_driver (driver_key)
);


-- =====================================================================
-- PASO 4 HEFESTO - Punto 1: volcado del archivo en tabla de staging
-- Archivo origen: df_fact_laps.csv (39.259 filas + encabezado, 32 columnas)
-- =====================================================================

DROP TABLE IF EXISTS stg_fact_laps;

# consigna 4.1.: prepara zona staging intermedia para volcar todos los datos del csv

CREATE TABLE stg_fact_laps (
    stg_id                  INT AUTO_INCREMENT PRIMARY KEY,
    -- columnas del CSV, mismo nombre y mismo orden
    meeting_key             VARCHAR(20),
    session_key             VARCHAR(20),
    driver_number           VARCHAR(20),
    lap_number              VARCHAR(20),
    lap_date_start          VARCHAR(40),
    i1_speed                VARCHAR(30),
    i2_speed                VARCHAR(30),
    is_pit_out_lap          VARCHAR(10),
    lap_duration            VARCHAR(40),
    st_speed                VARCHAR(40),
    full_name               VARCHAR(150),
    team_name               VARCHAR(100),
    position                VARCHAR(20),
    number_of_laps          VARCHAR(20),
    dnf                     VARCHAR(10),
    dns                     VARCHAR(10),
    dsq                     VARCHAR(10),
    session_total_duration  VARCHAR(30),
    gap_to_leader           VARCHAR(30),
    points                  VARCHAR(20),
    session_name            VARCHAR(100),
    session_type            VARCHAR(50),
    session_date_start      VARCHAR(40),
    session_date_end        VARCHAR(40),
    circuit_key             VARCHAR(20),
    circuit_short_name      VARCHAR(100),
    circuit_type            VARCHAR(50),
    country_name            VARCHAR(100),
    location                VARCHAR(150),
    session_year            VARCHAR(10),
    session_month           VARCHAR(10),
    session_day             VARCHAR(10)
);


-- --------------------------------------------------------------------------------------
-- CONTINUA PASO 4 HEFESTO: Verificación de la carga (guardar resultados como evidencia)
-- --------------------------------------------------------------------------------------
-- Coinsigna 4.2. Control de datos. 
SELECT COUNT(*) AS filas_cargadas FROM stg_fact_laps;   

SELECT * FROM stg_fact_laps LIMIT 20;

SELECT COUNT(*) FROM stg_fact_laps stg WHERE stg.lap_date_start IS NULL ;
describe stg_fact_laps;

-- ----------------------------------------------------------------------------
-- Crear view para retornar columnas stg_fact_laps a sus tipos datos originales
-- Creo una vista para no alterar la tabla original stg_fact_laps
-- ----------------------------------------------------------------------------

CREATE OR REPLACE VIEW view_stg_fact_laps AS
SELECT
    -- Claves y enteros
    stg_id,         
    CAST(meeting_key    AS UNSIGNED) AS meeting_key,
    CAST(session_key    AS UNSIGNED) AS session_key,
    CAST(driver_number  AS UNSIGNED) AS driver_number,
    CAST(lap_number     AS UNSIGNED) AS lap_number,
    CAST(circuit_key    AS UNSIGNED) AS circuit_key,

    -- Fecha y hora de la vuelta (valores en UTC)
    CAST(lap_date_start AS DATETIME(3)) AS lap_date_start,

    -- Métricas decimales (pueden tener nulos)
    -- NULLIF convierte texto vacio '' y/o 'NaN' en NULL antes implementar CAST , sino obtendriamos 0 falsos. 
    CAST(NULLIF(NULLIF(i1_speed,''),'nan')     AS DECIMAL(12,6)) AS i1_speed,   
    CAST(NULLIF(NULLIF(i2_speed,''),'nan')     AS DECIMAL(12,6)) AS i2_speed,
    CAST(NULLIF(NULLIF(st_speed,''),'nan')     AS DECIMAL(12,6)) AS st_speed,
    CAST(NULLIF(NULLIF(lap_duration,''),'nan') AS DECIMAL(12,6)) AS lap_duration,

    -- Booleanos (guardados como 1/0)
    CAST(is_pit_out_lap AS UNSIGNED) AS is_pit_out_lap,

    -- Piloto y equipo (texto). Sin CAST porque el tipo dato es varchar
    full_name, 
    team_name,

    -- Resultado de la sesión
    CAST(NULLIF(NULLIF(position,''),'nan')        AS UNSIGNED) AS position,
    CAST(NULLIF(NULLIF(number_of_laps,''),'nan')  AS UNSIGNED) AS number_of_laps,
    CAST(dnf AS UNSIGNED) AS dnf,
    CAST(dns AS UNSIGNED) AS dns,
    CAST(dsq AS UNSIGNED) AS dsq,
    CAST(NULLIF(NULLIF(session_total_duration,''),'nan') AS DECIMAL(12,6)) AS session_total_duration,
    CAST(NULLIF(NULLIF(gap_to_leader,''),'nan')          AS DECIMAL(12,6)) AS gap_to_leader,
    CAST(NULLIF(NULLIF(points,''),'nan')                 AS DECIMAL(6,2))  AS points,

    -- Sesión
	-- NULLIF convierte texto vacio '' y/o 'NaN' en NULL antes implementar CAST , sino obtendriamos 0 falsos. 
    session_name, -- sin CAST porque el tipo dato es varchar
    session_type, -- sin CAST porque el tipo dato es varchar
    CAST(session_date_start AS DATETIME(3)) AS session_date_start,
    CAST(session_date_end AS DATETIME(3)) AS session_date_end,
    CAST(session_year  AS UNSIGNED) AS session_year,
    CAST(session_month AS UNSIGNED) AS session_month,
    CAST(session_day   AS UNSIGNED) AS session_day,

    -- Circuito (texto). Sin CAST porque el tipo dato es varchar
    circuit_short_name,
    circuit_type,
    country_name,
    location

FROM stg_fact_laps;

-- ----------------------------------------------------------------------------
-- Comprobar view_stg_fact_laps se creo correctamente
-- ----------------------------------------------------------------------------
-- Mismas filas que stg_fact_laps (esperado: 39659)
SELECT COUNT(*) FROM view_stg_fact_laps;

-- Chequeo que nulos coinciden con pandas (i1_speed esperado: 4566; lap_date_start: 32)
SELECT
    SUM(i1_speed IS NULL) AS nulos_i1, -- esperado 4566
    SUM(i2_speed IS NULL) AS nulos_i2, -- esperado 497
    SUM(lap_date_start IS NULL) AS nulos_fecha
FROM view_stg_fact_laps;

-- Tipos datos resultantes luego de CAST
DESCRIBE view_stg_fact_laps;

-- ¿lap_date_start tiene valores 'nan'? verifico para eliminar nullif si lap_date_start no tiene 'nan' values
SELECT COUNT(*) FROM stg_fact_laps WHERE lap_date_start = 'nan';	

-- corroborar cantidad de nulos coincidan con cantidad de nulos en data frame python
SELECT
    SUM(meeting_key is null) as nulos_meeting_key,
    SUM(session_key is null) as nulos_session_key,
    SUM(driver_number IS NULL) as nulos_driver_number,
    SUM(lap_number is null) as nulos_lap_number,
    SUM(session_date_start IS NULL)    AS nulos_sess_ini,
    SUM(session_date_end IS NULL)      AS nulos_sess_fin,
    SUM(session_total_duration is null) as nulos_session_total_duration,
    SUM(lap_duration is null) as nulos_lap_duration
FROM view_stg_fact_laps;

-- corrobora que la suma coincida con la vista
select SUM(position IS NULL) AS nulos_position 
FROM view_stg_fact_laps;

select SUM(position IS NULL) AS nulos_position 
from view_stg_fact_laps;


-- ----------------------------------------------------------------------------
-- CONSINGNA 4.2.: TABLA PARA CALIDAD DE DATOS
-- ----------------------------------------------------------------------------

CREATE TABLE log_calidad_datos (
    id_log              INT AUTO_INCREMENT PRIMARY KEY,
    tabla               VARCHAR(50),
    columna             VARCHAR(50),
    que_se_busco        VARCHAR(200),
    cantidad_encontrada INT,
    fecha_chequeo       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO log_calidad_datos
(tabla, columna, que_se_busco, cantidad_encontrada)
VALUES
('view_stg_fact_laps', 'lap_date_start', 'Nulos en fecha de inicio de vuelta', 32);
 
INSERT INTO log_calidad_datos
(tabla, columna, que_se_busco, cantidad_encontrada)
VALUES
('view_stg_fact_laps', 'i1_speed', 'Nulos en el registro velocidad en el primer punto intermedio del seguimiento', 4566);
 
 INSERT INTO log_calidad_datos
(tabla, columna, que_se_busco, cantidad_encontrada)
VALUES
('view_stg_fact_laps', 'i2_speed', 'Nulos en el registro velocidad en el segundo punto intermedio del seguimiento', 497);
 
 INSERT INTO log_calidad_datos
(tabla, columna, que_se_busco, cantidad_encontrada)
VALUES
('view_stg_fact_laps', 'position', 'Nulos en posicion de pilotos', 1153);

-- ------------------------------------------------------------------------------------------------------------------------
-- CONSIGNA 4.4: POBLADO DATOS EN TABLAS DE HECHOS
-- ------------------------------------------------------------------------------------------------------------------------

INSERT INTO fact_rendimiento_piloto_session
    (date_key, meeting_key, session_key, driver_key,
     cantidad_vueltas, velocidad_media, lap_duration_medio, cantidad_salidas_pit)
SELECT
    CAST(DATE_FORMAT(v.session_date_start, '%Y%m%d') AS UNSIGNED) AS date_key,
    dm.meeting_key,
    ds.session_key,
    dd.driver_key,
    COUNT(*)                                AS cantidad_vueltas,
    ROUND(AVG(v.st_speed), 3)               AS velocidad_media,
    ROUND(AVG(v.lap_duration), 3)           AS lap_duration_medio,
    COALESCE(SUM(v.is_pit_out_lap), 0)      AS cantidad_salidas_pit
FROM view_stg_fact_laps v
JOIN dim_meeting dm ON dm.source_meeting_key = v.meeting_key
JOIN dim_session ds ON ds.source_session_key = v.session_key
JOIN dim_driver  dd ON dd.driver_number = v.driver_number
                   AND dd.full_name = COALESCE(v.full_name, 'Desconocido')
                   AND dd.team_name = COALESCE(v.team_name, 'Desconocido')
GROUP BY 1, 2, 3, 4;

-- --------------------------------------------------------------------------------------------------
-- # CONSIGNA 4.5 - Conteo de filas para control de datos
-- --------------------------------------------------------------------------------------------------

-- Verificar tablas dimensiones y hechos: Conteo cantidad filas sql == Conteo cantidad filas python 
SELECT 'dim_driver'  AS tabla, COUNT(*) AS filas FROM dim_driver
UNION ALL SELECT 'dim_session', COUNT(*) FROM dim_session
UNION ALL SELECT 'dim_meeting', COUNT(*) FROM dim_meeting
UNION ALL SELECT 'dim_date',    COUNT(*) FROM dim_date
UNION ALL SELECT 'fact_rendimiento_piloto_session', COUNT(*) FROM fact_rendimiento_piloto_session;

-- Verificar que no existen duplicados. Como la query incluye las PK , el conteo dara vacio si no existen duplicados
SELECT date_key, meeting_key, session_key, driver_key, COUNT(*) AS veces
FROM fact_rendimiento_piloto_session
GROUP BY date_key, meeting_key, session_key, driver_key
HAVING COUNT(*) > 1;

-- # Verificar cantidad de datos tabla de hechos. Debe coincidir con archivo df_fact_laps.csv
SELECT
    (SELECT SUM(cantidad_vueltas)     FROM fact_rendimiento_piloto_session) AS vueltas_dw,
    (SELECT SUM(cantidad_salidas_pit) FROM fact_rendimiento_piloto_session) AS salidas_pit_dw,
    (SELECT COUNT(*)                  FROM dim_driver)                      AS pilotos_dw;
    
