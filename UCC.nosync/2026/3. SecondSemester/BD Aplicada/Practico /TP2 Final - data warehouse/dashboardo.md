# DASHBOARD 

# Pregunta 1

**¿Como afecta el tipo de circuito a la velocidad media del piloto?**

## 1.1. Objetivo

Analizar el rendimiento del piloto. En este caso, cómo varía la velocidad media de cada piloto segun el equipo del que forman parte y tipo de circuito.

**Indicador:** velocidad media ponderada por la cantidad de vueltas, expresada en km/h.

## 1.1. Modelo de datos utilizado

La consulta se realiza exclusivamente sobre las tablas de dimensiones y hechos del Data Warehouse.

```mermaid
flowchart TD
    F["fact_rendimiento_piloto_session"]
    M["dim_meeting"]
    D["dim_driver"]

    F -->|"meeting_key"| M
    F -->|"driver_key"| D

    F --- I["Indicadores:<br/>velocidad_media<br/>cantidad_vueltas"]
    M --- C["Atributo:<br/>circuit_type"]
    D --- P["Atributos:<br/>full_name<br/>team_name"]
```

## Interpretación del gráfico

![Dashboard — Pregunta 1](img/img1.png)

Las columnas denotan el tipo de circuito (Permanente, Ruta, Calle). Las filas representan a cada piloto.  

- **Valores altos:** mayor velocidad media ponderada.
- **Valores bajos:** menor velocidad media ponderada.


La escala de colores representa la magnitud de la velocidad. Sin embargo hay que tener presenta que un valor alto no demuestra por sí solo que el tipo de circuito favorece al piloto, ya que hay muchas otras variables (clima, equipo, auto, etc) que no fueron contempladas en este analisis debido al poco tiempo de trabajo que se disponia.

------------
------------

# Pregunta 2 

**¿Afecta tipo de circuito a la duracion de vuelta de los equipos?**

## 2.1. Modelo Logico

```mermaid
flowchart TB
    subgraph Dimensiones
        D["dim_date<br/>PK date_key<br/>full_date<br/>day<br/>month<br/>year"]

        M["dim_meeting<br/>PK meeting_key<br/>source_meeting_key<br/>circuit_key<br/>circuit_short_name<br/>circuit_type<br/>country_name<br/>location"]

        S["dim_session<br/>PK session_key<br/>source_session_key<br/>session_name<br/>session_type<br/>is_cancelled"]

        DR["dim_driver<br/>PK driver_key<br/>driver_number<br/>full_name<br/>team_name"]
    end

    F["fact_rendimiento_piloto_session<br/><br/>FK date_key<br/>FK meeting_key<br/>FK session_key<br/>FK driver_key<br/><br/>cantidad_vueltas<br/>velocidad_media<br/>lap_duration_medio<br/>cantidad_salidas_pit"]

    D --> F
    M --> F
    S --> F
    DR --> F

    %% Fondo y texto del diagrama
    %% Dimensiones con recuadros grises
    %% Hechos con un gris más oscuro
    %% Flechas blancas

    classDef dimension fill:#555555,stroke:#AAAAAA,color:#FFFFFF,stroke-width:1.5px
    classDef fact fill:#333333,stroke:#FFFFFF,color:#FFFFFF,stroke-width:2px

    class D,M,S,DR dimension
    class F fact

    style Dimensiones fill:#222222,stroke:#888888,color:#FFFFFF,stroke-width:1.5px

    linkStyle default stroke:#FFFFFF,stroke-width:2px

    %% Tema oscuro general
    %% Aplicar fondo oscuro al diagrama
    %% según el renderizador Mermaid
```


## 2.2. Código Python

```python
from sqlalchemy import create_engine
import pandas as pd
import seaborn as sns
import matplotlib.pyplot as plt

engine = create_engine(
    "mysql+pymysql://root:TU_CONTRASEÑA@localhost:3306/dw_rendimiento_piloto"
)

query = """
SELECT
    m.circuit_type,
    dr.team_name,
    dr.full_name,
    ROUND(
        SUM(
            ((f.lap_duration_medio - p.promedio_sesion)
             / p.promedio_sesion * 100)
            * f.cantidad_vueltas
        ) / SUM(f.cantidad_vueltas),
        3
    ) AS pct_vs_promedio
FROM fact_rendimiento_piloto_session f

JOIN (
    SELECT
        session_key,
        SUM(lap_duration_medio * cantidad_vueltas)
            / SUM(cantidad_vueltas) AS promedio_sesion
    FROM fact_rendimiento_piloto_session
    WHERE lap_duration_medio IS NOT NULL
      AND cantidad_vueltas > 0
    GROUP BY session_key
) p
    ON f.session_key = p.session_key

JOIN dim_meeting m
    ON f.meeting_key = m.meeting_key

JOIN dim_driver dr
    ON f.driver_key = dr.driver_key

WHERE f.lap_duration_medio IS NOT NULL
  AND f.cantidad_vueltas > 0
  AND m.circuit_type IS NOT NULL

GROUP BY
    m.circuit_type,
    dr.team_name,
    dr.full_name

ORDER BY
    m.circuit_type,
    pct_vs_promedio;
"""

df = pd.read_sql(query, engine)
print(df.head(10))

# Preparar los datos para el mapa de calor
df["piloto_equipo"] = (
    df["full_name"] + " (" + df["team_name"] + ")"
)

tabla = df.pivot_table(
    index="piloto_equipo",
    columns="circuit_type",
    values="pct_vs_promedio"
)

# Ordenar de menor a mayor desviación porcentual
tabla = tabla.loc[
    tabla.mean(axis=1).sort_values().index
]

# Generar el mapa de calor
plt.figure(figsize=(9, 12))

sns.heatmap(
    tabla,
    annot=True,
    fmt=".2f",
    cmap="RdYlGn_r",
    center=0
)

plt.title(
    "¿Cómo rinde cada piloto según el tipo de circuito?\n"
    "(% vs promedio de la sesión; negativo = más rápido)"
)
plt.xlabel("Tipo de circuito")
plt.ylabel("Piloto (equipo)")
plt.tight_layout()
plt.show()
```

## 2.3. Interpretación del gráfico y Objetivo del analisis

![Dashboard — Pregunta 2](img/img2.png)

El objetivo del analisis es evaluar el rendimiento del piloto segun el circuito y el equipo al que forman parte.

Primero se calcula un promedio ponderado global correspondiente a la sesion, esto para tener un valor de referencia por sesion con el cual comparar el desempeño de cada piloto. <br>
Luego se calcula el lap_duration_medio ponderado para cada piloto y se le agrupo segun al equipo del que esta formando parte (por eso hay pilotos que aparecen mas de una vez). <br> 
lap_duration_medio por piloto denota el rendimiento del piloto durante una vuelta en una sesion entonces para calcular su rendimiento de la sesion completa se resta el promedio ponderado por vuelta al promedio ponderado global calculado y se lo divide por la cantidad de vueltas dadas por el piloto en esa sesion. <br>

**Valores Negativos**: representan un rendimiento del piloto muy bueno, ya que la media ponderada del piloto esta por debajo de la media ponderada global de la sesion.<br>
**Valores Positivos**: Indican que el rendimiento del piloto estuvo por encima de la media global ponderada de la sesion.<br>

Por lo tanto valores positivos mas alejados de cero indican menor rendimiento del piloto. Mientras que valores negativos indican rendimiento muy bueno del piloto.

------------
------------
# Pregunta 3 

**¿Que pilotos tienen mayor velocidad media por tipo de sesion?**

## 3.1. Modelo Logico

```mermaid
flowchart TB

    subgraph DIMENSIONES["Dimensiones"]
        direction LR

        DS["<b>dim_session</b><br/>PK session_key<br/>session_type"]

        DD["<b>dim_driver</b><br/>PK driver_key<br/>full_name<br/>team_name"]
    end

    subgraph HECHOS["Tabla de hechos"]
        FR["<b>fact_rendimiento_piloto_session</b><br/>FK session_key<br/>FK driver_key<br/>velocidad_media<br/>cantidad_vueltas"]
    end

    DS -->|"session_key"| FR
    DD -->|"driver_key"| FR

    classDef dimension fill:#DCEBFA,stroke:#3973AC,color:#1F2937
    classDef fact fill:#FCE8D5,stroke:#C47A32,color:#1F2937

    class DS,DD dimension
    class FR fact
```


## 3.2. Código Python

```python
query = """
    SELECT
        s.session_type,
        dr.full_name,
        dr.team_name,
        ROUND(SUM(f.velocidad_media * f.cantidad_vueltas)
              / SUM(f.cantidad_vueltas), 2) AS velocidad_ponderada,
        SUM(f.cantidad_vueltas) AS total_vueltas
    FROM fact_rendimiento_piloto_session f
    JOIN dim_session s ON f.session_key = s.session_key
    JOIN dim_driver dr ON f.driver_key  = dr.driver_key
    WHERE f.velocidad_media IS NOT NULL
      AND f.cantidad_vueltas > 0
    GROUP BY s.session_type, dr.full_name, dr.team_name
    HAVING SUM(f.cantidad_vueltas) >= 10
    ORDER BY s.session_type, velocidad_ponderada DESC
    """
    
    df = pd.read_sql(query, engine)
    print(df.head(50))
    
    df["piloto_equipo"] = df["full_name"] + " (" + df["team_name"] + ")"
    
    tipos = ["Qualifying", "Race"]
    fig, ejes = plt.subplots(1, 2, figsize=(16, 10))
    
    for eje, tipo in zip(ejes, tipos):
        sub = df[df["session_type"] == tipo].sort_values("velocidad_ponderada", ascending=False)
        sub = sub.head(15)  # top 15
    
        sns.barplot(data=sub, x="velocidad_ponderada", y="piloto_equipo",
                    hue="team_name", dodge=False, legend=False, ax=eje)
    
        # el eje X no empieza en 0 para que se noten las diferencias
        eje.set_xlim(sub["velocidad_ponderada"].min() - 5, sub["velocidad_ponderada"].max() + 2)
        eje.set_title(tipo)
        eje.set_xlabel("Velocidad media ponderada (km/h)")
        eje.set_ylabel("")
    
    fig.suptitle("¿Qué pilotos tienen mayor velocidad media según el tipo de sesión?")
    plt.tight_layout()
    plt.show()
```

## 3.3. Interpretación del gráfico y Objetivo del analisis

![Dashboard — Pregunta 3](img/img3.png)

El objetivo de este analisis es evaluar el desempeño de pilotos en cuanto a la velocidad media segun el tipo de sesion (Race o Qualifying)

Se agrupo a cada piloto segun equipo del que formaban parte. Por esta razon pilotos pueden aparecer mas de una vez en una mismo tipo de sesion. <br>

Se tienen dos graficos uno para Race y otro para Qualifying. Cada barra horizontal representa un piloto y entre parentesis el nombre del equipo en el cual estaban. El largo de cadda barra representa la velocidad media, en la parte inferior del grafico se encuentran los valores de velocidad media calculados. 

------------
------------
# Pregunta 4 

**¿Como evoluciona la velocidad media de cada piloto a lo largo de una temporada?**

## 4.1. Modelo Logico

```mermaid
flowchart TB

    subgraph DIMENSIONES["Dimensiones"]
        direction LR

        DD["<b>dim_date</b><br/>PK date_key<br/>year"]

        DS["<b>dim_session</b><br/>PK session_key<br/>session_type"]

        DR["<b>dim_driver</b><br/>PK driver_key<br/>full_name<br/>team_name"]
    end

    subgraph HECHOS["Tabla de hechos"]
        FR["<b>fact_rendimiento_piloto_session</b><br/>FK date_key<br/>FK session_key<br/>FK driver_key<br/>velocidad_media<br/>cantidad_vueltas"]
    end

    DD -->|"date_key"| FR
    DS -->|"session_key"| FR
    DR -->|"driver_key"| FR

    classDef dimension fill:#DCEBFA,stroke:#3973AC,color:#1F2937
    classDef fact fill:#FCE8D5,stroke:#C47A32,color:#1F2937

    class DD,DS,DR dimension
    class FR fact
```

## 4.2. Código Python

```python
query = """
SELECT
    d.`year` AS anio,
    s.session_type,
    dr.full_name,
    dr.team_name,
    ROUND(SUM(f.velocidad_media * f.cantidad_vueltas)
          / SUM(f.cantidad_vueltas), 2) AS velocidad_ponderada,
    SUM(f.cantidad_vueltas) AS total_vueltas
FROM fact_rendimiento_piloto_session f
JOIN dim_date d     ON f.date_key    = d.date_key
JOIN dim_session s  ON f.session_key = s.session_key
JOIN dim_driver dr  ON f.driver_key  = dr.driver_key
WHERE f.velocidad_media IS NOT NULL
  AND f.cantidad_vueltas > 0
GROUP BY d.`year`, s.session_type, dr.full_name, dr.team_name
HAVING SUM(f.cantidad_vueltas) >= 10
ORDER BY s.session_type, dr.full_name, d.`year`
"""

df = pd.read_sql(query, engine)
print(df.head(10))
print(df["anio"].unique())


anios = sorted(df["anio"].unique())
colores = sns.color_palette("viridis", len(anios))
nombres = {"Qualifying": "QUALIFYING",
           "Race": "RACE"}

fig, ejes = plt.subplots(2, 1, figsize=(18, 14))

for eje, tipo in zip(ejes, ["Qualifying", "Race"]):
    sub = df[df["session_type"] == tipo]

    # tablas: pilotos en filas, temporadas en columnas
    vel = sub.pivot_table(index="full_name", columns="anio",
                          values="velocidad_ponderada", aggfunc="mean")
    eq = sub.pivot_table(index="full_name", columns="anio",
                         values="team_name", aggfunc="first")

    # solo pilotos con al menos 2 temporadas (si no, no hay comparación)
    vel = vel[vel.notna().sum(axis=1) >= 2]
    vel = vel.loc[vel.mean(axis=1).sort_values(ascending=False).index]
    eq = eq.loc[vel.index]

    y_min = vel.min().min() - 10
    y_max = vel.max().max() + 3
    ancho = 0.8 / len(anios)
    x = np.arange(len(vel))

    for i, anio in enumerate(anios):
        pos = x - 0.4 + ancho * (i + 0.5)
        eje.bar(pos, vel[anio], ancho, color=colores[i], label=str(anio))
        for p, v, equipo in zip(pos, vel[anio], eq[anio]):
            if pd.notna(v):
                eje.text(p, y_min + 0.5, str(equipo)[:16], rotation=90,
                         ha="center", va="bottom", fontsize=7,
                         bbox=dict(facecolor="white", alpha=0.7,
                                   edgecolor="none", pad=1))

    eje.set_ylim(y_min, y_max)
    eje.set_xticks(x)
    eje.set_xticklabels(vel.index, rotation=60, ha="right")
    eje.set_title(nombres[tipo])
    eje.set_ylabel("Velocidad media ponderada (km/h)")
    eje.legend(title="Temporada", loc="upper right")

fig.suptitle("¿Cómo evolucionó la velocidad media de cada piloto por temporada?\n"
             "(el texto dentro de cada barra indica el equipo de ese año)")
plt.tight_layout()
plt.show()
```

## 4.3. Interpretación del gráfico y Objetivo del analisis

![Dashboard — Pregunta 4](img/img4.png)

Objetivo del analisis, comparar la evolucion de la velocidad media por temporada (2023, 2024, 2025, 2026) de cada piloto segun el equipo y el tipo de sesion (Race o Qualifying). Por eso se considero una grafico de barras ya que este grafico permite hacer una comparar del piloto consigo mismo y con un simple vistazo podemor decir si el piloto mejoro su velocidad media y la disminuyo. <br>

------------
------------
# Pregunta 5

**Por meeting ¿Que equipo tiene mejor rendimiento en vueltas en sesiones tipo Race?**

## 5.1. Modelo Logico


## 5.2. Código Python

```python
query_circuitos = """
SELECT m.circuit_short_name,
       COUNT(DISTINCT d.`year`) AS temporadas
FROM fact_rendimiento_piloto_session f
JOIN dim_meeting m ON f.meeting_key = m.meeting_key
JOIN dim_date d    ON f.date_key    = d.date_key
JOIN dim_session s ON f.session_key = s.session_key
WHERE s.session_name = 'Race'
GROUP BY m.circuit_short_name
ORDER BY temporadas DESC, m.circuit_short_name
"""
print(pd.read_sql(query_circuitos, engine))

circuito = "Monza"

query = f"""
SELECT
    d.`year` AS anio,
    dr.team_name,
    SUM(f.cantidad_vueltas) AS total_vueltas
FROM fact_rendimiento_piloto_session f
JOIN dim_meeting m ON f.meeting_key = m.meeting_key
JOIN dim_date d    ON f.date_key    = d.date_key
JOIN dim_session s ON f.session_key = s.session_key
JOIN dim_driver dr ON f.driver_key  = dr.driver_key
WHERE m.circuit_short_name = '{circuito}'
  AND s.session_name = 'Race'
GROUP BY d.`year`, dr.team_name
ORDER BY d.`year`, total_vueltas DESC
"""
df = pd.read_sql(query, engine)
print(df)

from matplotlib.patches import Patch

# un color fijo por equipo, igual en todas las tortas
equipos = sorted(df["team_name"].unique())
colores = dict(zip(equipos, sns.color_palette("tab20", len(equipos))))

anios = sorted(df["anio"].unique())
fig, ejes = plt.subplots(1, len(anios), figsize=(5 * len(anios), 6), squeeze=False)

for eje, anio in zip(ejes[0], anios):
    sub = df[df["anio"] == anio].sort_values("total_vueltas", ascending=False)
    eje.pie(sub["total_vueltas"],
            colors=[colores[t] for t in sub["team_name"]],
            autopct="%1.1f%%", startangle=90, counterclock=False,
            wedgeprops={"edgecolor": "white"}, textprops={"fontsize": 8})
    eje.set_title(f"{anio}\n({int(sub['total_vueltas'].sum())} vueltas en total)")

fig.legend(handles=[Patch(color=c, label=t) for t, c in colores.items()],
           loc="lower center", ncol=5)
fig.suptitle(f"¿Qué equipo completó más vueltas en la carrera de {circuito}, año a año?")
plt.tight_layout(rect=[0, 0.1, 1, 0.93])
plt.show()
```

## 5.3. Interpretación del gráfico y Objetivo del analisis

![Dashboard — Pregunta 5](img/img5.png)

Objetivo, analizar la evolucion en el tiempo del rendimiento de los equipos en diferentes circuito. <br> 
En este analisis, rendimiento denota volumen, es decir, cantidad de vueltas completadas por equipo en un determinado circuito. Se busca estudiar la confianza del equipo para terminar diferentes carreras. <br>
Se decidio un grafico de torta porque por cada temporada se tienen varias meeting en diferetes circuitos. Cada meeting tiene un total global de vueltas que representa el 100% de las vueltas. Entonces asignando un porcentaje de torta a cada equipo segun las cantidades de vueltas dadas, se puede visualizar rapidamente si un equipo ha ido evolucionando en las cantidades de vueltas con el transcurso del tiempo. 

## 5.4. OBSERVACION DEL CODIGO 
Si quisiera analizar el rendimiento en otro circuito, debe cambiarse el nombre del circuito. Por ejemplo de circuito = "Monza" a circuito = "Las Vegas".
Se deja una lista con todos los circuitos disponibles: Baku ,Catalunya ,Hungaroring ,Melbourne, Miami, Monte Carlo, Montreal, Monza, Silverstone, Spa-Francorchamps, Spielberg , Suzuka, Zandvoort, Austin, Interlagos, Jeddah, Las Vegas,Lusail, Mexico City, Sakhir, Shanghai, Singapore, Yas Marina Circuit, Imola, Kuala Lumpur, Madring. 

