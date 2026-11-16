-- =====================================================================
-- CONSIGNA 3 - METODOLOGIA HEFESTO
-- Modelo lógico DW: fact_rendimiento_piloto_session
-- =====================================================================

CREATE DATABASE IF NOT EXISTS dw_rendimiento_piloto
    DEFAULT CHARACTER SET utf8mb4
    DEFAULT COLLATE utf8mb4_0900_ai_ci;

USE dw_rendimiento_piloto;

-- Para poder re-ejecutar el script (primero se elimina el hecho por las FK)
DROP TABLE IF EXISTS fact_rendimiento_piloto_session;
DROP TABLE IF EXISTS dim_date;
DROP TABLE IF EXISTS dim_meeting;
DROP TABLE IF EXISTS dim_session;
DROP TABLE IF EXISTS dim_driver;

-- ---------------------------------------------------------------------
-- DIMENSIONES
-- ---------------------------------------------------------------------

CREATE TABLE dim_date (
    date_key    INT  NOT NULL AUTO_INCREMENT,
    full_date   DATE NOT NULL,
    `day`       INT  NOT NULL,
    `month`     INT  NOT NULL,
    `year`      INT  NOT NULL,
    PRIMARY KEY (date_key),
    UNIQUE KEY uq_dim_date_full_date (full_date)
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
    full_name      VARCHAR(150) NOT NULL,
    team_name      VARCHAR(100) NOT NULL,
    PRIMARY KEY (driver_key)
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
    lane_duration_medio DECIMAL(10,3) NULL,
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

USE dw_rendimiento_piloto;

DROP TABLE IF EXISTS stg_fact_laps_raw;

CREATE TABLE stg_fact_laps_raw (
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
    session_day             VARCHAR(10),
    -- auditoría de la carga
    _source_file            VARCHAR(255) NULL,
    _loaded_at              TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ---------------------------------------------------------------------
-- Verificación de la carga (guardar resultados como evidencia)
-- ---------------------------------------------------------------------
SELECT COUNT(*) AS filas_cargadas FROM stg_fact_laps_raw;   -- esperado: 39259

SELECT * FROM stg_fact_laps_raw LIMIT 20;

-- Perfilado: valores esperados según el archivo
SELECT COUNT(DISTINCT meeting_key)   AS meetings,       -- 85
       COUNT(DISTINCT session_key)   AS sesiones,       -- 215
       COUNT(DISTINCT circuit_key)   AS circuitos,      -- 25
       COUNT(DISTINCT driver_number) AS numeros_piloto, -- 6
       COUNT(DISTINCT CONCAT_WS('|', driver_number, full_name, team_name)) AS combinaciones_piloto_equipo -- 10
FROM stg_fact_laps_raw;

-- Vacíos detectados en el archivo (a resolver en la etapa de limpieza)
SELECT SUM(lap_date_start = '')   AS lap_date_start_vacia,   -- 32
       SUM(i1_speed = '')         AS i1_speed_vacia,         -- 4537
       SUM(i2_speed = '')         AS i2_speed_vacia,         -- 496
       SUM(position = '')         AS position_vacia,         -- 1153
       SUM(number_of_laps = '')   AS number_of_laps_vacia,   -- 164
       SUM(session_total_duration = '') AS total_duration_vacia, -- 2636
       SUM(gap_to_leader = '')    AS gap_vacia               -- 2680
FROM stg_fact_laps_raw;

CREATE USER 'dw_user'@'localhost' IDENTIFIED BY 'dw_clave_123';
GRANT ALL PRIVILEGES ON dw_rendimiento_piloto.* TO 'dw_user'@'localhost';
FLUSH PRIVILEGES;
