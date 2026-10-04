# Goal
The goal of this project is to build a Shiny dashboard in R that lets users visualize and understand patterns in Colorado's water resources. The original essential question was how much water trans-mountain diversions move and how much water leaves the state. However, the scope is larger now and includes things like storage, flow, and historical use. 

Stage 2 is deploying the beta version of the Shiny app on the Posit hosting service. Moving ETL pipelines into Github Actions, and setting up the database structure and read/write on AWS S3.

 Stage 3 of the project will include incorporating gridded climate data and precipitation data, including SNOTEL, to be able to perform basic basin water balance modeling. And adding other features as we see fit. 

# Work plan

## Stage One 
- Stage one is getting the ETL pipelines, API calls, and the beta Shiny dashboard running locally on my dev machine.
- Stage one is focused on the Transmountain diversions as well as a few critical river gauges
- There is already some existing code, including a list of all Transmountain WDIDs for accessing data from the Colorado CDSS system. 
- For stage one, files will be written as Parquet files in the project data folder; the data structure should be transferable to the cloud, as later stages will move into an S3 bucket
- Later, GitHub Actions will automate the API calls to update the database, so development at this stage should keep that in mind

### The shiny dashboard 
should be scientific and clean but use beautiful and compelling visuals. The dashboard should be interesting and useful to a water resource professional but accessible to the public. It should include an interactive map that lets users select features, view current data, and compare it with historical data. For the map base, let's use the NHDPlus hydrofabric. The dashboard will also have other tabs added as the project progresses. 

### Data sourcing

Source data from the following 
- CDSS API 
- USGS API through the data retrieval package
- US Bureau of Reclamation (if needed)
